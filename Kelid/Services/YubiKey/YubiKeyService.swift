import CryptoKit
import Foundation

/// CTAP2 enrollment for a hardware security key, talking raw CTAPHID over USB.
///
/// Milestone-2 scope: detect the key, read its capabilities (`getInfo`), and
/// create a discoverable credential with the **hmac-secret** extension
/// (`makeCredential`). The returned credential id is what a later milestone uses
/// with `getAssertion` to derive a hardware-backed secret that wraps the master
/// keyslot — the same FIDO2 hmac-secret design Svault used. No PIN/UV flow yet;
/// if the key requires user verification we surface that honestly.
nonisolated enum YubiKeyService {
    struct Enrollment: Codable {
        var credentialIDBase64: String
        var rpID: String
        var enrolledAt: Date
        var aaguidHex: String
    }

    enum EnrollError: LocalizedError {
        case notPresent
        case userVerificationRequired
        case noHmacSecretSupport
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notPresent:
                "No security key detected. Insert your YubiKey and try again."
            case .userVerificationRequired:
                "This key requires a PIN. PIN-protected enrollment arrives in a later milestone."
            case .noHmacSecretSupport:
                "This security key does not support the hmac-secret extension Kelid needs."
            case .failed(let why):
                "Enrollment failed: \(why)"
            }
        }
    }

    private static let rpID = "kelid.local"

    // CTAP2 command bytes
    private enum CtapCmd {
        static let makeCredential: UInt8 = 0x01
        static let getInfo: UInt8 = 0x04
    }

    static var isKeyPresent: Bool {
        FidoHidDevice.isKeyPresent
    }

    /// Runs the full enrollment off the main actor (USB I/O blocks on the
    /// user's touch). Returns the stored enrollment record.
    static func enroll() async throws -> Enrollment {
        try await Task.detached(priority: .userInitiated) {
            try runEnroll()
        }.value
    }

    private nonisolated static func runEnroll() throws -> Enrollment {
        guard FidoHidDevice.isKeyPresent else { throw EnrollError.notPresent }

        let device: FidoHidDevice
        do {
            device = try FidoHidDevice.open()
        } catch {
            throw EnrollError.failed(error.localizedDescription)
        }

        try assertHmacSecret(device)
        return try makeCredential(device)
    }

    // MARK: - getInfo

    private nonisolated static func assertHmacSecret(_ device: FidoHidDevice) throws {
        let response: [UInt8]
        do {
            response = try device.sendCBOR(command: CtapCmd.getInfo, body: [])
        } catch {
            throw EnrollError.failed(error.localizedDescription)
        }
        guard let info = try? CBOR.decode(response),
              case .array(let extensions)? = info.mapValue(forInt: 2)
        else { return } // older keys omit the list; let makeCredential be the real test

        let names = extensions.compactMap { if case .text(let s) = $0 { return s } else { return nil } }
        if !names.isEmpty, !names.contains("hmac-secret") {
            throw EnrollError.noHmacSecretSupport
        }
    }

    // MARK: - makeCredential

    private nonisolated static func makeCredential(_ device: FidoHidDevice) throws -> Enrollment {
        var clientDataHashBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &clientDataHashBytes)

        var userID = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &userID)

        // CTAP2 makeCredential: integer-keyed map (canonical CBOR).
        let request = CBOR.Value.map([
            (.unsigned(1), .bytes(clientDataHashBytes)),                  // clientDataHash
            (.unsigned(2), .map([                                         // rp
                (.text("id"), .text(rpID)),
                (.text("name"), .text("Kelid")),
            ])),
            (.unsigned(3), .map([                                         // user
                (.text("id"), .bytes(userID)),
                (.text("name"), .text("kelid-master")),
                (.text("displayName"), .text("Kelid Master")),
            ])),
            (.unsigned(4), .array([                                       // pubKeyCredParams: ES256
                .map([(.text("alg"), .negative(-7)), (.text("type"), .text("public-key"))]),
            ])),
            (.unsigned(6), .map([                                         // extensions
                (.text("hmac-secret"), .bool(true)),
            ])),
            (.unsigned(7), .map([                                         // options: rk = true
                (.text("rk"), .bool(true)),
            ])),
        ])

        let body = CBOR.encode(request)
        let response: [UInt8]
        do {
            response = try device.sendCBOR(command: CtapCmd.makeCredential, body: body)
        } catch let FidoHidDevice.HidError.protocolError(message) {
            // 0x36 = PIN required, 0x37 = PIN invalid, 0x6A = UV required
            if message.contains("0x36") || message.contains("0x6a") {
                throw EnrollError.userVerificationRequired
            }
            throw EnrollError.failed(message)
        } catch {
            throw EnrollError.failed(error.localizedDescription)
        }

        let (credentialID, aaguid) = try parseCredentialID(from: response)
        let enrollment = Enrollment(
            credentialIDBase64: Data(credentialID).base64EncodedString(),
            rpID: rpID,
            enrolledAt: .now,
            aaguidHex: aaguid.map { String(format: "%02x", $0) }.joined()
        )
        try save(enrollment)
        return enrollment
    }

    /// Pulls the credential id out of the attestation object's authData.
    /// authData layout: rpIdHash(32) flags(1) signCount(4) then
    /// attestedCredentialData = aaguid(16) credIdLen(2 BE) credId(L) ...
    private nonisolated static func parseCredentialID(from response: [UInt8]) throws -> (id: [UInt8], aaguid: [UInt8]) {
        guard let attestation = try? CBOR.decode(response),
              let authData = attestation.mapValue(forInt: 1)?.bytesValue
        else { throw EnrollError.failed("no authData in attestation") }

        let credDataStart = 37 // 32 + 1 + 4
        guard authData.count >= credDataStart + 18 else {
            throw EnrollError.failed("authData too short for attested credential")
        }
        let aaguid = Array(authData[credDataStart..<credDataStart + 16])
        let lenIndex = credDataStart + 16
        let credLen = Int(authData[lenIndex]) << 8 | Int(authData[lenIndex + 1])
        let idStart = lenIndex + 2
        guard authData.count >= idStart + credLen else {
            throw EnrollError.failed("authData too short for credential id")
        }
        return (Array(authData[idStart..<idStart + credLen]), aaguid)
    }

    // MARK: - Persistence

    private nonisolated static var recordURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
            .appendingPathComponent("yubikey.json")
    }

    static var enrollment: Enrollment? {
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONDecoder().decode(Enrollment.self, from: data)
    }

    static var isEnrolled: Bool { enrollment != nil }

    private nonisolated static func save(_ enrollment: Enrollment) throws {
        let dir = recordURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(enrollment)
        try data.write(to: recordURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
    }

    static func removeEnrollment() {
        try? FileManager.default.removeItem(at: recordURL)
    }
}
