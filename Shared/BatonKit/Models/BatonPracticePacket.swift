import Foundation

nonisolated struct BatonPracticePacket {
    static let characteristicUUID = "12345678-1234-5678-1234-56789ABCDEF5"
    enum State: UInt8 { case idle, active, transitioning, failed, calibrating }
    let state: State
    let holdSequence: UInt8
    let commandSequence: UInt16
    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count == 6, (bytes[0] == 1 || bytes[0] == 2), bytes[3] == 0,
              let state = State(rawValue: bytes[1]),
              bytes[0] == 2 || state != .calibrating else { return nil }
        self.state = state
        holdSequence = bytes[2]
        commandSequence = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
    }
    static func command(active: Bool, sequence: UInt16) -> Data {
        Data([1, active ? 1 : 0, UInt8(truncatingIfNeeded: sequence), UInt8(sequence >> 8)])
    }
}
