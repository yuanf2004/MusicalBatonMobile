import Foundation

/// A bounded recording of decoded packets, with device-time rollover handling.
struct MotionHistory {
    struct Sample: Identifiable {
        let id: UInt64
        let elapsedMilliseconds: UInt64
        let packet: BatonMotionPacket
        let accelerationSegment: UInt64
        let gyroscopeSegment: UInt64
    }

    private(set) var samples: [Sample] = []
    private(set) var receivedCount: UInt64 = 0
    private(set) var lastIntervalMilliseconds: UInt32?
    private(set) var clockResetCount: UInt64 = 0
    private var elapsedMilliseconds: UInt64 = 0
    private var accelerationSegment: UInt64 = 0
    private var gyroscopeSegment: UInt64 = 0

    mutating func append(_ packet: BatonMotionPacket) {
        receivedCount += 1
        if let previous = samples.last?.packet {
            // Reads may return the same sample as the latest notification.
            if previous.sequence == packet.sequence && previous.uptimeMilliseconds == packet.uptimeMilliseconds {
                return
            }
            let delta = packet.uptimeMilliseconds &- previous.uptimeMilliseconds
            if delta > UInt32.max / 2 {
                // A backwards clock/reboot is distinct from a normal 32-bit wrap.
                samples.removeAll()
                elapsedMilliseconds = 0
                lastIntervalMilliseconds = nil
                accelerationSegment = 0
                gyroscopeSegment = 0
                clockResetCount += 1
            } else {
                elapsedMilliseconds += UInt64(delta)
                let gapThreshold = max(UInt64(1000), UInt64(lastIntervalMilliseconds ?? delta) * 3)
                if packet.sequence &- previous.sequence != 1 || UInt64(delta) > gapThreshold {
                    accelerationSegment += 1
                    gyroscopeSegment += 1
                }
                if delta > 0 { lastIntervalMilliseconds = delta }
            }
        }
        // Invalid groups create a line break rather than plotting zero or bridging it.
        if !packet.accelerationValid { accelerationSegment += 1 }
        if !packet.gyroscopeValid { gyroscopeSegment += 1 }
        samples.append(Sample(id: receivedCount, elapsedMilliseconds: elapsedMilliseconds,
                              packet: packet, accelerationSegment: accelerationSegment,
                              gyroscopeSegment: gyroscopeSegment))
        let cutoff = elapsedMilliseconds > 60_000 ? elapsedMilliseconds - 60_000 : 0
        if let firstKept = samples.firstIndex(where: { $0.elapsedMilliseconds >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
        if samples.count > 1000 { samples.removeFirst(samples.count - 1000) }
    }

    func visibleSamples(seconds: Double) -> [Sample] {
        let span = UInt64(max(0, seconds) * 1000)
        let cutoff = elapsedMilliseconds > span ? elapsedMilliseconds - span : 0
        return samples.filter { $0.elapsedMilliseconds >= cutoff }
    }
}

enum MotionChannel: String, CaseIterable, Identifiable {
    case accelerationX, accelerationY, accelerationZ, gyroscopeX, gyroscopeY, gyroscopeZ
    var id: Self { self }
    var isAcceleration: Bool {
        switch self {
        case .accelerationX, .accelerationY, .accelerationZ: true
        default: false
        }
    }
    var axis: String {
        switch self {
        case .accelerationX, .gyroscopeX: "X"
        case .accelerationY, .gyroscopeY: "Y"
        case .accelerationZ, .gyroscopeZ: "Z"
        }
    }
    var title: String { "\(isAcceleration ? "Acceleration" : "Gyroscope") \(axis)" }
    var unit: String { isAcceleration ? "mg" : "°/s" }
    func value(in packet: BatonMotionPacket) -> Double? {
        guard isAcceleration ? packet.accelerationValid : packet.gyroscopeValid else { return nil }
        let axes = isAcceleration ? packet.acceleration : packet.gyroscope
        let raw: Int16
        switch axis {
        case "X": raw = axes.x
        case "Y": raw = axes.y
        default: raw = axes.z
        }
        return Double(raw) / (isAcceleration ? 1 : 10)
    }
    func segment(in sample: MotionHistory.Sample) -> UInt64 {
        isAcceleration ? sample.accelerationSegment : sample.gyroscopeSegment
    }
}
