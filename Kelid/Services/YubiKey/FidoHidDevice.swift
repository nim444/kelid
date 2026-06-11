import Foundation
import IOKit.hid

/// USB HID transport for FIDO2/CTAPHID. Finds a FIDO device (HID usage page
/// 0xF1D0), opens it, and exchanges CTAPHID frames (64-byte reports with the
/// init/continuation framing from the CTAPHID spec).
nonisolated final class FidoHidDevice {
    enum HidError: LocalizedError {
        case notFound
        case openFailed(IOReturn)
        case writeFailed(IOReturn)
        case timeout
        case channelFailed
        case protocolError(String)

        var errorDescription: String? {
            switch self {
            case .notFound: "No FIDO security key found. Insert your YubiKey and try again."
            case .openFailed: "Could not open the security key."
            case .writeFailed: "Could not send data to the security key."
            case .timeout: "The security key did not respond. Touch it when it blinks."
            case .channelFailed: "Could not establish a channel with the security key."
            case .protocolError(let why): "Security key protocol error: \(why)"
            }
        }
    }

    // CTAPHID command bytes
    enum Cmd: UInt8 {
        case ping = 0x81
        case msg = 0x83
        case `init` = 0x86
        case cbor = 0x90
        case cancel = 0x91
        case keepalive = 0xBB
        case error = 0xBF
    }

    private static let fidoUsagePage: UInt32 = 0xF1D0
    private static let reportSize = 64
    private static let broadcastChannel: UInt32 = 0xFFFFFFFF

    private let device: IOHIDDevice
    private var channel: UInt32 = broadcastChannel
    private var inputBuffer = [UInt8]()
    private let bufferLock = NSCondition()
    private var reportBacking: UnsafeMutablePointer<UInt8>

    private init(device: IOHIDDevice) {
        self.device = device
        self.reportBacking = .allocate(capacity: Self.reportSize)
        self.reportBacking.initialize(repeating: 0, count: Self.reportSize)
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBacking.deinitialize(count: Self.reportSize)
        reportBacking.deallocate()
    }

    static var isKeyPresent: Bool {
        (try? locateDevice()) != nil
    }

    /// Opens the first FIDO device and negotiates a CTAPHID channel.
    static func open() throws -> FidoHidDevice {
        let hidDevice = try locateDevice()
        let dev = FidoHidDevice(device: hidDevice)
        guard IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw HidError.openFailed(kIOReturnNotOpen)
        }
        dev.registerInputCallback()
        try dev.initChannel()
        return dev
    }

    // MARK: - Device discovery

    private static func locateDevice() throws -> IOHIDDevice {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDDeviceUsagePageKey: fidoUsagePage]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let first = set.first else {
            throw HidError.notFound
        }
        return first
    }

    // MARK: - Input plumbing

    private func registerInputCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBacking, Self.reportSize,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let me = Unmanaged<FidoHidDevice>.fromOpaque(context).takeUnretainedValue()
                me.bufferLock.lock()
                me.inputBuffer.append(contentsOf: UnsafeBufferPointer(start: report, count: length))
                me.bufferLock.signal()
                me.bufferLock.unlock()
            },
            context
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    // MARK: - Channel init

    private func initChannel() throws {
        var nonce = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &nonce)
        let response = try transact(cmd: .`init`, payload: nonce)
        guard response.count >= 17 else { throw HidError.channelFailed }
        // [0..<8] echoed nonce, [8..<12] assigned channel id
        guard Array(response[0..<8]) == nonce else { throw HidError.channelFailed }
        channel = response[8...11].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    // MARK: - CTAP2 entry point

    /// Sends a CTAP2 CBOR command (command byte + CBOR body) and returns the
    /// response payload (status byte stripped, CBOR body returned).
    func sendCBOR(command: UInt8, body: [UInt8]) throws -> [UInt8] {
        let response = try transact(cmd: .cbor, payload: [command] + body)
        guard let status = response.first else { throw HidError.protocolError("empty CBOR response") }
        guard status == 0x00 else {
            throw HidError.protocolError("CTAP2 status 0x\(String(status, radix: 16))")
        }
        return Array(response.dropFirst())
    }

    // MARK: - Framing

    private func transact(cmd: Cmd, payload: [UInt8]) throws -> [UInt8] {
        try writeFrames(cmd: cmd, payload: payload)
        return try readResponse(expected: cmd)
    }

    private func writeFrames(cmd: Cmd, payload: [UInt8]) throws {
        var report = [UInt8]()
        // Initialization packet: channel(4) cmd(1) len(2) data...
        report += beBytes(channel)
        report.append(cmd.rawValue)
        report.append(UInt8(payload.count >> 8 & 0xFF))
        report.append(UInt8(payload.count & 0xFF))
        let firstChunk = payload.prefix(Self.reportSize - 7)
        report += firstChunk
        try sendReport(padded(report))

        var offset = firstChunk.count
        var seq: UInt8 = 0
        while offset < payload.count {
            var cont = beBytes(channel)
            cont.append(seq & 0x7F)
            let chunk = payload[offset..<min(offset + Self.reportSize - 5, payload.count)]
            cont += chunk
            try sendReport(padded(cont))
            offset += chunk.count
            seq += 1
        }
    }

    private func readResponse(expected: Cmd) throws -> [UInt8] {
        while true {
            let initPacket = try readReport()
            guard initPacket.count >= 7 else { throw HidError.protocolError("short init packet") }
            let cmdByte = initPacket[4]
            let length = Int(initPacket[5]) << 8 | Int(initPacket[6])

            if cmdByte == Cmd.keepalive.rawValue {
                continue // device is waiting for the user's touch; keep reading
            }
            if cmdByte == Cmd.error.rawValue {
                let code = initPacket.count > 7 ? initPacket[7] : 0
                throw HidError.protocolError("CTAPHID error 0x\(String(code, radix: 16))")
            }

            var data = Array(initPacket[7...])
            if data.count > length { data = Array(data[0..<length]) }
            while data.count < length {
                let cont = try readReport()
                guard cont.count >= 5 else { throw HidError.protocolError("short cont packet") }
                let remaining = length - data.count
                let slice = Array(cont[5...].prefix(remaining))
                data += slice
            }
            return data
        }
    }

    // MARK: - Report I/O

    private func sendReport(_ report: [UInt8]) throws {
        let result = report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf.baseAddress!, buf.count)
        }
        guard result == kIOReturnSuccess else { throw HidError.writeFailed(result) }
    }

    private func readReport(timeout: TimeInterval = 12) throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        bufferLock.lock()
        defer { bufferLock.unlock() }
        while inputBuffer.count < Self.reportSize {
            if !bufferLock.wait(until: deadline) {
                throw HidError.timeout
            }
        }
        let frame = Array(inputBuffer.prefix(Self.reportSize))
        inputBuffer.removeFirst(Self.reportSize)
        return frame
    }

    private func padded(_ report: [UInt8]) -> [UInt8] {
        var out = report
        if out.count < Self.reportSize {
            out += [UInt8](repeating: 0, count: Self.reportSize - out.count)
        }
        return out
    }

    private func beBytes(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }
}
