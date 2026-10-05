import Foundation

// Matches bluetooth_publish() and the flag definitions in the baton firmware.
struct BatonMotionPacket {
    static let serviceUUID = "12345678-1234-5678-1234-56789ABCDEF0"
    static let characteristicUUID = "12345678-1234-5678-1234-56789ABCDEF1"

    struct Axes {
        let x: Int16
        let y: Int16
        let z: Int16

        var milligravityText: String { "X: \(x)   Y: \(y)   Z: \(z) mg" }
        var degreesPerSecondText: String {
            String(format: "X: %.1f   Y: %.1f   Z: %.1f °/s", Double(x) / 10, Double(y) / 10, Double(z) / 10)
        }
    }

    let version: UInt8
    let flags: UInt8
    let sequence: UInt16
    let uptimeMilliseconds: UInt32
    let acceleration: Axes
    let gyroscope: Axes

    var accelerationValid: Bool { flags & 0x01 != 0 }
    var gyroscopeValid: Bool { flags & 0x02 != 0 }
    var timeSynchronized: Bool { flags & 0x04 != 0 }
    var unknownFlags: UInt8 { flags & 0xF8 }

    static func matches(serviceUUID: String?, characteristicUUID: String) -> Bool {
        serviceUUID?.uppercased() == self.serviceUUID && characteristicUUID.uppercased() == self.characteristicUUID
    }

    init(data: Data) throws {
        guard data.count == 20 else { throw DecodeError.invalidLength(data.count) }
        // Byte-wise decoding avoids alignment, native-endian, and Data slice issues.
        let bytes = Array(data)
        guard bytes[0] == 1 else { throw DecodeError.unsupportedVersion(bytes[0]) }
        func unsigned16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func signed16(_ offset: Int) -> Int16 { Int16(bitPattern: unsigned16(offset)) }
        version = bytes[0]
        flags = bytes[1]
        sequence = unsigned16(2)
        uptimeMilliseconds = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8)
            | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        acceleration = Axes(x: signed16(8), y: signed16(10), z: signed16(12))
        gyroscope = Axes(x: signed16(14), y: signed16(16), z: signed16(18))
    }

    var logSummary: String {
        let accel = accelerationValid ? acceleration.milligravityText : "invalid"
        let gyro = gyroscopeValid ? gyroscope.degreesPerSecondText : "invalid"
        return "Motion v\(version) seq=\(sequence) uptime=\(uptimeMilliseconds) ms flags=\(String(format: "%02X", flags)) | Accel: \(accel) | Gyro: \(gyro) | Time synced: \(timeSynchronized ? "yes" : "no")"
    }

    enum DecodeError: LocalizedError {
        case invalidLength(Int)
        case unsupportedVersion(UInt8)

        var errorDescription: String? {
            switch self {
            case .invalidLength(let count): "Expected a 20-byte baton motion packet; received \(count) bytes."
            case .unsupportedVersion(let version): "Unsupported baton packet version \(version). This app decodes version 1."
            }
        }
    }
}
