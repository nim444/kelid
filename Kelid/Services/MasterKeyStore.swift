import CommonCrypto
import CryptoKit
import Foundation

/// Creates and verifies the master passphrase record and issues the one-time
/// recovery code.
///
/// Verifier: PBKDF2-HMAC-SHA256, 600k rounds (OWASP 2023), 32-byte salt, via
/// CommonCrypto's vetted implementation. One-way only — the passphrase itself
/// is never stored. The crypto core milestone layers Argon2id keyslots and
/// vault DEKs on top (see docs/svault-export/architecture.md).
enum MasterKeyStore {
    struct MasterRecord: Codable {
        var kdf: String
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

    private nonisolated static let iterations = 600_000
    private nonisolated static let kdfName = "pbkdf2-hmac-sha256"

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

        let salt = randomBytes(32)
        let verifier = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: passphrase, salt: salt, rounds: iterations)
        }.value

        let recoveryCode = generateRecoveryCode()
        let recoveryHash = Data(SHA256.hash(data: Data(recoveryCode.utf8)))

        let record = MasterRecord(
            kdf: kdfName,
            saltBase64: salt.base64EncodedString(),
            verifierBase64: verifier.base64EncodedString(),
            recoveryHashBase64: recoveryHash.base64EncodedString(),
            iterations: iterations,
            createdAt: .now
        )
        try write(record)
        return recoveryCode
    }

    static func verify(passphrase: String) async -> Bool {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(MasterRecord.self, from: data),
              record.kdf == kdfName,
              let salt = Data(base64Encoded: record.saltBase64),
              let stored = Data(base64Encoded: record.verifierBase64)
        else { return false }

        let rounds = record.iterations
        let candidate = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: passphrase, salt: salt, rounds: rounds)
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
        let salt = randomBytes(32)
        let verifier = await Task.detached(priority: .userInitiated) {
            deriveVerifier(passphrase: new, salt: salt, rounds: iterations)
        }.value
        record.kdf = kdfName
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
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
            let data = try JSONEncoder().encode(record)
            try data.write(to: recordURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        } catch {
            throw MasterError.storageFailed(error.localizedDescription)
        }
    }

    /// PBKDF2-HMAC-SHA256 via CommonCrypto (vetted, FIPS-validated path).
    private nonisolated static func deriveVerifier(passphrase: String, salt: Data, rounds: Int) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase, passphrase.utf8.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(rounds),
            &out, out.count
        )
        precondition(status == kCCSuccess, "PBKDF2 derivation failed (\(status))")
        return Data(out)
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
    /// Rejection sampling keeps every character exactly equiprobable.
    private nonisolated static func generateRecoveryCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var groups: [String] = []
        for _ in 0..<8 {
            var group = ""
            for _ in 0..<4 {
                group.append(alphabet[uniformRandom(below: alphabet.count)])
            }
            groups.append(group)
        }
        return groups.joined(separator: "-")
    }

    /// Unbiased random index in 0..<bound via rejection sampling.
    private nonisolated static func uniformRandom(below bound: Int) -> Int {
        let limit = 256 - (256 % bound)
        while true {
            var byte: UInt8 = 0
            _ = withUnsafeMutableBytes(of: &byte) {
                SecRandomCopyBytes(kSecRandomDefault, 1, $0.baseAddress!)
            }
            if Int(byte) < limit { return Int(byte) % bound }
        }
    }
}
