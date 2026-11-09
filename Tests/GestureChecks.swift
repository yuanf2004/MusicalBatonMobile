import Foundation

@main
struct GestureChecks {
    struct Fixture: Decodable {
        let samples: [[Double]]
        let features: [Double]
        let label: String
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let tree = try GestureTree.load(data: Data(contentsOf: root.appendingPathComponent("Shared/BatonKit/Conducting/gesture_v1.json")))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Tests/gesture_parity.json")))
        for fixture in fixtures {
            let features = GestureTree.features(fixture.samples)
            for (actual, expected) in zip(features, fixture.features) {
                precondition(abs(actual-expected) <= 1e-8 * max(1, abs(expected)))
            }
            precondition(tree.predict(features: features) == fixture.label)
        }
        precondition(BeatPlaybackPolicy.rejection(strength: 50, threshold: 50, mode: .peak, label: nil) != nil)
        precondition(BeatPlaybackPolicy.rejection(strength: 51, threshold: 50, mode: .peak, label: nil) == nil)
        precondition(BeatPlaybackPolicy.rejection(strength: 80, threshold: 50, mode: .gesture, label: "idle") != nil)
        precondition(BeatPlaybackPolicy.rejection(strength: 80, threshold: 50, mode: .gesture, label: nil) != nil)
        for label in ["down", "left", "right", "diagonal_up"] {
            precondition(BeatPlaybackPolicy.rejection(strength: 80, threshold: 50, mode: .gesture, label: label) == nil)
        }
        func packet(_ sequence: UInt16, _ time: UInt32, valid: Bool = true) -> BatonMotionPacket {
            var bytes: [UInt8] = [1, valid ? 3 : 0, UInt8(truncatingIfNeeded: sequence), UInt8(sequence >> 8)]
            bytes += (0..<4).map { UInt8(truncatingIfNeeded: time >> ($0*8)) }
            bytes += [0,0,0,0,0xE8,3,0,0,0,0,0,0]
            return try! BatonMotionPacket(data: Data(bytes))
        }
        var filter = GestureFilter(tree: tree)
        for i in 0..<3 { filter.add(packet(UInt16(i), UInt32(i*53)), receivedAt: Double(i)*0.053) }
        precondition(filter.label == nil)
        filter.add(packet(3, 159), receivedAt: 0.159)
        precondition(filter.currentLabel(at: 0.159) != nil)
        precondition(filter.currentLabel(at: 0.5) == nil) // Stale host delivery.
        filter.add(packet(5, 265), receivedAt: 0.265) // Lost motion packet clears votes.
        precondition(filter.label == nil)
        for i in 6...8 { filter.add(packet(UInt16(i), UInt32(i*53)), receivedAt: Double(i)*0.053) }
        precondition(filter.label != nil) // Automatically recovers; no reset button.
        filter.add(packet(9, 477, valid: false), receivedAt: 0.477)
        precondition(filter.label == nil)
        filter.reset()
        for i in 0..<5 {
            filter.add(packet(UInt16(truncatingIfNeeded: 65533+i), (UInt32.max-100) &+ UInt32(i*50)), receivedAt: Double(i)*0.05)
        }
        precondition(filter.label != nil) // Both clocks and sequence wrap.
        filter.reset()
        precondition(filter.currentLabel(at: 0.2) == nil)
        print("Gesture parity passed for \(fixtures.count) Python windows; strength, idle, warmup, stale data, gaps, recovery and wrap passed")
    }
}
