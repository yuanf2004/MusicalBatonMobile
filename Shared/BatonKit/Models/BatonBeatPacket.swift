import Foundation

// Firmware notify-only beat event, independent of the 20-byte motion packet.
nonisolated struct BatonBeatPacket: Sendable {
    static let serviceUUID = "12345678-1234-5678-1234-56789ABCDEF0"
    static let characteristicUUID = "12345678-1234-5678-1234-56789ABCDEF2"
    let sequence: UInt16
    let uptimeMilliseconds: UInt32
    let bpmTenths: UInt16
    let strength: UInt8

    static func matches(serviceUUID: String?, characteristicUUID: String) -> Bool {
        serviceUUID?.uppercased() == self.serviceUUID && characteristicUUID.uppercased() == self.characteristicUUID
    }

    init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count == 12, bytes[0] == 1, bytes[1] == 1,
              bytes[10] <= 100, bytes[11] == 0 else { throw DecodeError.invalid }
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8) }
        sequence = u16(2)
        uptimeMilliseconds = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8)
            | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        bpmTenths = u16(8)
        strength = bytes[10]
    }

    enum DecodeError: LocalizedError {
        case invalid
        var errorDescription: String? { "Invalid beat packet: expected 12 bytes, version/type 1, strength 0–100, and reserved byte 0." }
    }
}

// Observe packets even while sound is disabled, so toggling the mode cannot
// turn a duplicate into a fresh beat. A new connection resets this state.
nonisolated struct BeatEventGate {
    private var previous: BatonBeatPacket?

    mutating func accept(_ packet: BatonBeatPacket) -> Bool {
        if let previous {
            let sequenceDelta = packet.sequence &- previous.sequence
            let timeDelta = packet.uptimeMilliseconds &- previous.uptimeMilliseconds
            guard sequenceDelta > 0, sequenceDelta < 0x8000,
                  timeDelta > 0, timeDelta < 0x8000_0000 else { return false }
        }
        previous = packet
        return true
    }
}
