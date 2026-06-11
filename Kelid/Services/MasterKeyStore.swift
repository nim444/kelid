import CryptoKit
import Foundation

/// Creates and verifies the master passphrase record and issues the one-time
/// recovery code.
///
/// Milestone-1 scaffold: the stored verifier is salted iterated SHA-256.
/// This is a stand-in until the crypto core lands (Argon2id keyslots and
/// vault DEKs wrapped under the master key — see docs/svault-export/architecture.md).
/// Nothing here is presented as final crypto.
enum MasterKeyStore {
    struct MasterRecord: Codable {
        var saltBase64: String
        var verifierBase64: String
        var recoveryHashBase64: String
        var iterations: Int
        var createdAt: Date
    }

    enum MasterError: LocalizedError {
        case alreadyExists
        case notFound
        case wrongPassphrase
        case storageFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyExists: "A master passphrase already exists."
            case .notFound: "No master passphrase is set up yet."
            case .wrongPassphrase: "That current passphrase is not correct."
            case .storageFailed(let why): "Could not store the master record: \(why)"
            }
        }
    }

    private nonisolated static let iterations = 120_000

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
    }

    private static var recordURL: URL {
        supportDirectory.appendingPathComponent("master.json")
    }

    static var masterExists: Bool {
        FileManager.default.fileExists(atPath: recordURL.path)
    }

    /// Creates the master record and returns the one-time recovery code.
    /// The code is never stored in plaintext — only its hash, for later verification.
    static func create(passphrase: String) async throws -> String {
        guard !masterExists else { throw MasterError.alreadyExists }

        let salt = randomBytes(16)
        let verifier = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: passphrase, salt: salt)
        }.value

        let recoveryCode = generateRecoveryCode()
        let recoveryHash = Data(SHA256.hash(data: Data(recoveryCode.utf8)))

        let record = MasterRecord(
            saltBase64: salt.base64EncodedString(),
            verifierBase64: verifier.base64EncodedString(),
            recoveryHashBase64: recoveryHash.base64EncodedString(),
            iterations: iterations,
            createdAt: .now
        )

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: recordURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        } catch {
            throw MasterError.storageFailed(error.localizedDescription)
        }
        return recoveryCode
    }

    static func verify(passphrase: String) async -> Bool {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(MasterRecord.self, from: data),
              let salt = Data(base64Encoded: record.saltBase64),
              let stored = Data(base64Encoded: record.verifierBase64)
        else { return false }

        let candidate = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: passphrase, salt: salt)
        }.value
        return constantTimeEquals(candidate, stored)
    }

    // MARK: - Mutations (Settings)

    /// Re-derives the verifier under a fresh salt for a new passphrase.
    /// Verifies the current passphrase first; the recovery hash is untouched.
    static func changePassphrase(current: String, new: String) async throws {
        guard masterExists else { throw MasterError.notFound }
        guard await verify(passphrase: current) else { throw MasterError.wrongPassphrase }

        var record = try loadRecord()
        let salt = randomBytes(16)
        let verifier = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: new, salt: salt)
        }.value
        record.saltBase64 = salt.base64EncodedString()
        record.verifierBase64 = verifier.base64EncodedString()
        record.iterations = iterations
        try write(record)
    }

    /// Mints a brand-new recovery code, stores only its hash, and returns the
    /// code to show once. Requires the current passphrase — the old code (which
    /// was never stored in plaintext) stops working immediately.
    static func regenerateRecoveryCode(currentPassphrase: String) async throws -> String {
        guard masterExists else { throw MasterError.notFound }
        guard await verify(passphrase: currentPassphrase) else { throw MasterError.wrongPassphrase }

        var record = try loadRecord()
        let code = generateRecoveryCode()
        let hash = Data(SHA256.hash(data: Data(code.utf8)))
        record.recoveryHashBase64 = hash.base64EncodedString()
        try write(record)
        return code
    }

    // MARK: - Helpers

    private static func loadRecord() throws -> MasterRecord {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(MasterRecord.self, from: data)
        else { throw MasterError.storageFailed("Could not read the master record.") }
        return record
    }

    private static func write(_ record: MasterRecord) throws {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: recordURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        } catch {
            throw MasterError.storageFailed(error.localizedDescription)
        }
    }

    private nonisolated static func deriveVerifier(passphrase: String, salt: Data) -> Data {
        var digest = Data(salt + Data(passphrase.utf8))
        for _ in 0..<iterations {
            digest = Data(SHA256.hash(data: digest))
        }
        return digest
    }

    private nonisolated static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    private nonisolated static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// 8 groups of 4 from an unambiguous alphabet (no I, L, O, 0, 1).
    private nonisolated static func generateRecoveryCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var groups: [String] = []
        for _ in 0..<8 {
            var group = ""
            for _ in 0..<4 {
                var index: UInt32 = 0
                _ = withUnsafeMutableBytes(of: &index) {
                    SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!)
                }
                group.append(alphabet[Int(index) % alphabet.count])
            }
            groups.append(group)
        }
        return groups.joined(separator: "-")
    }
}
