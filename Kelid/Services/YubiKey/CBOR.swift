import Foundation

/// Minimal CBOR encode/decode, scoped to what CTAP2 needs (canonical maps with
/// integer or text keys, byte/text strings, arrays, unsigned/negative ints,
/// bools). Not a general-purpose CBOR library.
nonisolated enum CBOR {
    enum Value {
        case unsigned(UInt64)
        case negative(Int64)
        case bytes([UInt8])
        case text(String)
        case array([Value])
        case map([(Value, Value)])
        case bool(Bool)
        case null
    }

    enum CBORError: Error {
        case truncated
        case unsupportedMajorType(UInt8)
        case malformed(String)
    }

    // MARK: - Encoding

    static func encode(_ value: Value) -> [UInt8] {
        switch value {
        case .unsigned(let n):
            return encodeTypeAndLength(major: 0, value: n)
        case .negative(let n):
            return encodeTypeAndLength(major: 1, value: UInt64(-1 - n))
        case .bytes(let b):
            return encodeTypeAndLength(major: 2, value: UInt64(b.count)) + b
        case .text(let s):
            let utf8 = Array(s.utf8)
            return encodeTypeAndLength(major: 3, value: UInt64(utf8.count)) + utf8
        case .array(let items):
            var out = encodeTypeAndLength(major: 4, value: UInt64(items.count))
            for item in items { out += encode(item) }
            return out
        case .map(let pairs):
            // CTAP2 canonical CBOR: keys sorted by encoded bytes.
            let encodedPairs = pairs.map { (encode($0.0), encode($0.1)) }
                .sorted { lhs, rhs in canonicalKeyLess(lhs.0, rhs.0) }
            var out = encodeTypeAndLength(major: 5, value: UInt64(pairs.count))
            for pair in encodedPairs { out += pair.0 + pair.1 }
            return out
        case .bool(let flag):
            return [flag ? 0xF5 : 0xF4]
        case .null:
            return [0xF6]
        }
    }

    private static func canonicalKeyLess(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        if a.count != b.count { return a.count < b.count }
        for (x, y) in zip(a, b) where x != y { return x < y }
        return false
    }

    private static func encodeTypeAndLength(major: UInt8, value: UInt64) -> [UInt8] {
        let high = major << 5
        switch value {
        case ..<24:
            return [high | UInt8(value)]
        case ..<0x100:
            return [high | 24, UInt8(value)]
        case ..<0x1_0000:
            return [high | 25, UInt8(value >> 8), UInt8(value & 0xFF)]
        case ..<0x1_0000_0000:
            return [high | 26] + beBytes(UInt32(value))
        default:
            return [high | 27] + beBytes(value)
        }
    }

    private static func beBytes(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private static func beBytes(_ v: UInt64) -> [UInt8] {
        (0..<8).reversed().map { UInt8(v >> (UInt64($0) * 8) & 0xFF) }
    }

    // MARK: - Decoding

    static func decode(_ bytes: [UInt8]) throws -> Value {
        var cursor = 0
        let value = try decodeValue(bytes, &cursor)
        return value
    }

    private static func decodeValue(_ bytes: [UInt8], _ cursor: inout Int) throws -> Value {
        guard cursor < bytes.count else { throw CBORError.truncated }
        let initial = bytes[cursor]; cursor += 1
        let major = initial >> 5
        let info = initial & 0x1F

        switch major {
        case 0:
            return .unsigned(try readLength(bytes, &cursor, info))
        case 1:
            return .negative(-1 - Int64(try readLength(bytes, &cursor, info)))
        case 2:
            let n = Int(try readLength(bytes, &cursor, info))
            return .bytes(try take(bytes, &cursor, n))
        case 3:
            let n = Int(try readLength(bytes, &cursor, info))
            let raw = try take(bytes, &cursor, n)
            return .text(String(decoding: raw, as: UTF8.self))
        case 4:
            let count = Int(try readLength(bytes, &cursor, info))
            var items: [Value] = []
            for _ in 0..<count { items.append(try decodeValue(bytes, &cursor)) }
            return .array(items)
        case 5:
            let count = Int(try readLength(bytes, &cursor, info))
            var pairs: [(Value, Value)] = []
            for _ in 0..<count {
                let key = try decodeValue(bytes, &cursor)
                let val = try decodeValue(bytes, &cursor)
                pairs.append((key, val))
            }
            return .map(pairs)
        case 7:
            switch info {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22: return .null
            default: throw CBORError.malformed("unsupported simple value \(info)")
            }
        default:
            throw CBORError.unsupportedMajorType(major)
        }
    }

    private static func readLength(_ bytes: [UInt8], _ cursor: inout Int, _ info: UInt8) throws -> UInt64 {
        switch info {
        case ..<24:
            return UInt64(info)
        case 24:
            return UInt64(try take(bytes, &cursor, 1)[0])
        case 25:
            let b = try take(bytes, &cursor, 2)
            return UInt64(b[0]) << 8 | UInt64(b[1])
        case 26:
            let b = try take(bytes, &cursor, 4)
            return b.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        case 27:
            let b = try take(bytes, &cursor, 8)
            return b.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        default:
            throw CBORError.malformed("bad length info \(info)")
        }
    }

    private static func take(_ bytes: [UInt8], _ cursor: inout Int, _ n: Int) throws -> [UInt8] {
        guard cursor + n <= bytes.count else { throw CBORError.truncated }
        defer { cursor += n }
        return Array(bytes[cursor..<cursor + n])
    }
}

nonisolated extension CBOR.Value {
    /// Look up an integer-keyed map entry (CTAP2 responses use integer keys).
    func mapValue(forInt key: UInt64) -> CBOR.Value? {
        guard case .map(let pairs) = self else { return nil }
        for (k, v) in pairs {
            if case .unsigned(let n) = k, n == key { return v }
        }
        return nil
    }

    var bytesValue: [UInt8]? {
        if case .bytes(let b) = self { return b }
        return nil
    }
}
