import CommonCrypto
import CryptoKit
import Foundation

/// CTAP2 PIN/UV Auth Protocol **v1** — enough to obtain a pinUvAuthToken so
/// `makeCredential` can carry a `pinUvAuthParam` on a PIN-protected key.
///
/// v1 KDF: sharedSecret = SHA-256(ECDH-X). Encryption: AES-256-CBC, zero IV,
/// no padding. Authentication: HMAC-SHA-256 truncated to 16 bytes.
nonisolated enum CtapPinProtocol {
    enum PinError: LocalizedError {
        case noKeyAgreement
        case badAuthenticatorKey
        case pinInvalid(retries: Int?)
        case pinBlocked
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noKeyAgreement: "The security key did not return a key-agreement key."
            case .badAuthenticatorKey: "The security key sent an unreadable public key."
            case .pinInvalid(let retries):
                if let retries { "Wrong PIN. \(retries) attempt\(retries == 1 ? "" : "s") left before the key locks." }
                else { "Wrong PIN." }
            case .pinBlocked: "Too many wrong PINs — the key is locked. Remove and reinsert it, then reset its PIN."
            case .failed(let why): "PIN handshake failed: \(why)"
            }
        }
    }

    static let protocolVersion: UInt64 = 1

    private enum ClientPINCmd {
        static let command: UInt8 = 0x06
        static let getKeyAgreement: UInt64 = 0x02
        static let getPINToken: UInt64 = 0x05
    }

    /// Runs the v1 handshake against the device and returns the pinUvAuthToken.
    static func establishToken(device: FidoHidDevice, pin: String) throws -> Data {
        // 1. Ask the authenticator for its key-agreement public key.
        let kaRequest = CBOR.Value.map([
            (.unsigned(1), .unsigned(protocolVersion)),
            (.unsigned(2), .unsigned(ClientPINCmd.getKeyAgreement)),
        ])
        let kaResponse = try device.sendCBOR(command: ClientPINCmd.command, body: CBOR.encode(kaRequest))
        guard let decoded = try? CBOR.decode(kaResponse),
              let coseKey = decoded.mapValue(forInt: 1)
        else { throw PinError.noKeyAgreement }

        let authPublic = try parseCOSE(coseKey)

        // 2. Platform ephemeral key + ECDH; v1 shared secret = SHA-256(X).
        let platformPrivate = P256.KeyAgreement.PrivateKey()
        let shared: SymmetricKey
        do {
            let z = try platformPrivate.sharedSecretFromKeyAgreement(with: authPublic)
            let zBytes = z.withUnsafeBytes { Data($0) }
            shared = SymmetricKey(data: Data(SHA256.hash(data: zBytes)))
        } catch {
            throw PinError.failed(error.localizedDescription)
        }

        // 3. pinHashEnc = AES-256-CBC(sharedSecret, IV0, LEFT16(SHA-256(pin))).
        // Best-effort zeroization of key material once the handshake finishes.
        var pinHash = Array(SHA256.hash(data: Data(pin.utf8)).prefix(16))
        var sharedBytes = shared.withUnsafeBytes { Array($0) }
        defer {
            for i in pinHash.indices { pinHash[i] = 0 }
            for i in sharedBytes.indices { sharedBytes[i] = 0 }
        }
        let pinHashEnc = try aesCBC(key: sharedBytes, data: pinHash, encrypt: true)

        // 4. getPINToken.
        let platformCOSE = encodeCOSE(platformPrivate.publicKey)
        let tokenRequest = CBOR.Value.map([
            (.unsigned(1), .unsigned(protocolVersion)),
            (.unsigned(2), .unsigned(ClientPINCmd.getPINToken)),
            (.unsigned(3), platformCOSE),
            (.unsigned(6), .bytes(pinHashEnc)),
        ])

        let tokenResponse: [UInt8]
        do {
            tokenResponse = try device.sendCBOR(command: ClientPINCmd.command, body: CBOR.encode(tokenRequest))
        } catch let FidoHidDevice.HidError.protocolError(message) {
            throw mapPinStatus(message)
        }

        guard let tokenDecoded = try? CBOR.decode(tokenResponse),
              let encToken = tokenDecoded.mapValue(forInt: 2)?.bytesValue
        else { throw PinError.failed("no PIN token in response") }

        // 5. Decrypt the pinUvAuthToken.
        let token = try aesCBC(key: sharedBytes, data: encToken, encrypt: false)
        return Data(token)
    }

    /// pinUvAuthParam = LEFT16(HMAC-SHA-256(token, message)).
    static func authenticate(token: Data, message: [UInt8]) -> [UInt8] {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message), using: SymmetricKey(data: token))
        return Array(Data(mac).prefix(16))
    }

    // MARK: - COSE

    private static func parseCOSE(_ key: CBOR.Value) throws -> P256.KeyAgreement.PublicKey {
        guard let x = key.value(forKey: -2)?.bytesValue,
              let y = key.value(forKey: -3)?.bytesValue,
              x.count == 32, y.count == 32
        else { throw PinError.badAuthenticatorKey }
        let x963 = Data([0x04] + x + y)
        guard let pub = try? P256.KeyAgreement.PublicKey(x963Representation: x963) else {
            throw PinError.badAuthenticatorKey
        }
        return pub
    }

    private static func encodeCOSE(_ key: P256.KeyAgreement.PublicKey) -> CBOR.Value {
        let x963 = key.x963Representation // 0x04 || X(32) || Y(32)
        let x = Array(x963[1..<33])
        let y = Array(x963[33..<65])
        // kty=EC2(2), alg=ECDH-ES+HKDF-256(-25), crv=P-256(1), x, y
        return .map([
            (.unsigned(1), .unsigned(2)),
            (.unsigned(3), .negative(-25)),
            (.negative(-1), .unsigned(1)),
            (.negative(-2), .bytes(x)),
            (.negative(-3), .bytes(y)),
        ])
    }

    // MARK: - AES-256-CBC, zero IV, no padding (CommonCrypto)

    private static func aesCBC(key: [UInt8], data: [UInt8], encrypt: Bool) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let status = CCCrypt(
            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(0), // CBC, no padding
            key, key.count,
            iv,
            data, data.count,
            &out, out.count,
            &moved
        )
        guard status == kCCSuccess else { throw PinError.failed("AES-CBC error \(status)") }
        return Array(out.prefix(moved))
    }

    // MARK: - Status mapping

    private static func mapPinStatus(_ message: String) -> PinError {
        let m = message.lowercased()
        if m.contains("0x31") { return .pinInvalid(retries: nil) } // PIN_INVALID
        if m.contains("0x34") { return .pinBlocked }               // PIN_AUTH_BLOCKED
        if m.contains("0x32") { return .pinBlocked }               // PIN_BLOCKED
        return .failed(message)
    }
}
