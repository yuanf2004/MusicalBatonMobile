import Foundation

@main
struct ConductingChecks {
    static func main() throws {
        func bytes(_ sequence: UInt16, _ time: UInt32, bpm: UInt16 = 0) -> Data {
            Data([1, 1, UInt8(truncatingIfNeeded: sequence), UInt8(sequence >> 8),
                  UInt8(truncatingIfNeeded: time), UInt8(truncatingIfNeeded: time >> 8),
                  UInt8(truncatingIfNeeded: time >> 16), UInt8(truncatingIfNeeded: time >> 24),
                  UInt8(truncatingIfNeeded: bpm), UInt8(bpm >> 8), 83, 0])
        }
        let fixture = bytes(0x1234, 0x12345678, bpm: 1000)
        let packet = try BatonBeatPacket(data: fixture)
        precondition(packet.sequence == 0x1234 && packet.uptimeMilliseconds == 0x12345678)
        precondition(packet.bpmTenths == 1000 && packet.strength == 83)
        precondition(BatonBeatPacket.matches(serviceUUID: BatonBeatPacket.serviceUUID.lowercased(),
                                            characteristicUUID: BatonBeatPacket.characteristicUUID))
        precondition(!BatonBeatPacket.matches(serviceUUID: "180F", characteristicUUID: BatonBeatPacket.characteristicUUID))
        var prefixed = Data([0xFF]); prefixed.append(fixture)
        let sliced = try BatonBeatPacket(data: prefixed.dropFirst())
        precondition(sliced.sequence == packet.sequence)
        var invalids = [Data(), fixture.dropLast(), fixture + Data([0])]
        for (index, value) in [(0, UInt8(2)), (1, UInt8(2)), (10, UInt8(101)), (11, UInt8(1))] {
            var invalid = fixture; invalid[index] = value; invalids.append(invalid)
        }
        for data in invalids {
            do { _ = try BatonBeatPacket(data: data); fatalError("Accepted malformed beat") }
            catch BatonBeatPacket.DecodeError.invalid {}
        }
        var gate = BeatEventGate()
        precondition(gate.accept(packet))
        precondition(!gate.accept(packet))
        let older = try BatonBeatPacket(data: bytes(0x1233, 0x12345600))
        precondition(!gate.accept(older))
        let next = try BatonBeatPacket(data: bytes(0x1235, 0x12345678 + 600))
        precondition(gate.accept(next)) // Zero BPM still means a valid sound event.
        let sameTime = try BatonBeatPacket(data: bytes(0x1236, next.uptimeMilliseconds))
        precondition(!gate.accept(sameTime))
        gate = BeatEventGate()
        let beforeWrap = try BatonBeatPacket(data: bytes(65535, UInt32.max - 100))
        let afterWrap = try BatonBeatPacket(data: bytes(0, 499))
        precondition(gate.accept(beforeWrap) && gate.accept(afterWrap))
        precondition(!gate.accept(beforeWrap))
        let wav = BeatSound.wavData()
        precondition(wav.count == 44 + 2646 * 2)
        precondition(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        precondition(String(data: wav[8..<12], encoding: .ascii) == "WAVE")
        precondition(wav[22] == 1 && wav[34] == 16)
        precondition(wav.suffix(2) == Data([0, 0]))
        print("Conducting packet, sequence, wrap, zero-BPM, and sound checks passed")
    }
}
