import Foundation

@main struct PracticePacketChecks {
    static func main() {
        for active in [false, true] {
            for sequence: UInt16 in [0, 255, 256, 65535] {
                let command = BatonPracticePacket.command(active: active, sequence: sequence)
                precondition(Array(command) == [1, active ? 1 : 0, UInt8(truncatingIfNeeded: sequence), UInt8(sequence >> 8)])
                let status = BatonPracticePacket(data: Data([1, active ? 1 : 0, 255, 0, command[2], command[3]]))!
                precondition(status.commandSequence == sequence && status.holdSequence == 255)
                precondition(status.state == (active ? .active : .idle))
            }
        }
        for bytes: [UInt8] in [[], [1, 0], [3, 0, 0, 0, 0, 0], [1, 4, 0, 0, 0, 0], [1, 0, 0, 1, 0, 0], [1, 0, 0, 0, 0, 0, 0]] {
            precondition(BatonPracticePacket(data: Data(bytes)) == nil)
        }
        precondition(BatonPracticePacket(data: Data([1, 2, 0, 0, 0, 0]))?.state == .transitioning)
        precondition(BatonPracticePacket(data: Data([1, 3, 0, 0, 0, 0]))?.state == .failed)
        precondition(BatonPracticePacket(data: Data([2, 4, 0, 0, 0, 0]))?.state == .calibrating)
        precondition(BatonPracticePacket(data: Data([2, 1, 0, 0, 0, 0]))?.state == .active)
        print("Practice protocol versions, lengths, states, reserved bytes and sequence boundaries passed")
    }
}
