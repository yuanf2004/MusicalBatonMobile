import Foundation

nonisolated enum BeatFilterMode: String, CaseIterable, Identifiable {
    case peak = "Peak + strength"
    case gesture = "Peak + ML (experimental)"
    var id: String { rawValue }
}

// Exact v1 decision tree exported from Zach ec6c752. Model data stays local.
nonisolated struct GestureTree: Decodable {
    struct Node: Decodable {
        let left: Int
        let right: Int
        let feature: Int
        let threshold: Double
        let label: String
    }
    let version: Int
    let sourceSHA256: String
    let windowMS: Int
    let featureNames: [String]
    let nodes: [Node]

    static func load(data: Data) throws -> Self {
        let tree = try JSONDecoder().decode(Self.self, from: data)
        guard tree.version == 1, tree.windowMS == 200, tree.featureNames.count == 48,
              !tree.nodes.isEmpty else { throw ModelError.invalid }
        let labels = Set(["idle", "down", "left", "right", "diagonal_up"])
        for (i, node) in tree.nodes.enumerated() {
            guard labels.contains(node.label), node.threshold.isFinite else { throw ModelError.invalid }
            if node.left == -1 {
                guard node.right == -1 else { throw ModelError.invalid }
            } else {
                guard (0..<48).contains(node.feature), node.left > i, node.right > i,
                      node.left < tree.nodes.count, node.right < tree.nodes.count else { throw ModelError.invalid }
            }
        }
        return tree
    }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "gesture_v1", withExtension: "json") else {
            throw ModelError.missing
        }
        return try load(data: Data(contentsOf: url))
    }

    func predict(features: [Double]) -> String {
        precondition(features.count == 48)
        var index = 0
        while nodes[index].left != -1 {
            let node = nodes[index]
            // sklearn casts inputs to float32 before comparing double thresholds.
            index = Double(Float(features[node.feature])) <= node.threshold ? node.left : node.right
        }
        return nodes[index].label
    }

    static func features(_ samples: [[Double]]) -> [Double] {
        precondition(!samples.isEmpty && samples.allSatisfy { $0.count == 6 })
        let rows = samples.map { row in
            row + [sqrt(row[0]*row[0] + row[1]*row[1] + row[2]*row[2]),
                   sqrt(row[3]*row[3] + row[4]*row[4] + row[5]*row[5])]
        }
        return (0..<8).flatMap { axis -> [Double] in
            let values = rows.map { $0[axis] }
            let n = Double(values.count)
            let mean = values.reduce(0, +) / n
            let variance = values.reduce(0) { $0 + ($1-mean)*($1-mean) } / n
            let minimum = values.min()!
            let maximum = values.max()!
            let rms = sqrt(values.reduce(0) { $0 + $1*$1 } / n)
            return [mean, sqrt(variance), minimum, maximum, rms, maximum-minimum]
        }
    }

    enum ModelError: LocalizedError {
        case invalid, missing
        var errorDescription: String? { "The bundled gesture model is missing or invalid. Select Peak + strength or reinstall the app." }
    }
}

// Bounded recent history. Same 200 ms features and five-vote rule as the PC.
// BLE adaptation: >=4 actual samples spanning >=140 ms instead of USB's >=6/170 ms.
// No interpolation or invented measurements. Accuracy at BLE rate is unvalidated.
nonisolated struct GestureFilter {
    let tree: GestureTree
    private var samples: [(time: UInt32, values: [Double])] = []
    private var votes: [String] = []
    private var previousSequence: UInt16?
    private(set) var label: String?
    private(set) var lastReceived: TimeInterval?

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        votes.removeAll(keepingCapacity: true)
        previousSequence = nil
        label = nil
        lastReceived = nil
    }

    mutating func add(_ packet: BatonMotionPacket, receivedAt: TimeInterval) {
        guard packet.accelerationValid, packet.gyroscopeValid else { reset(); return }
        if let last = samples.last, let sequence = previousSequence {
            let dt = packet.uptimeMilliseconds &- last.time
            let ds = packet.sequence &- sequence
            // Ignore duplicates/out-of-order deliveries; a long gap clears old votes.
            if dt == 0 || ds == 0 { return }
            if dt >= 0x8000_0000 || ds >= 0x8000 { reset(); return }
            if dt > 100 || ds != 1 || receivedAt - (lastReceived ?? receivedAt) > 0.25 { reset() }
        }
        let a = packet.acceleration
        let g = packet.gyroscope
        samples.append((packet.uptimeMilliseconds, [Double(a.x), Double(a.y), Double(a.z),
                                                   Double(g.x), Double(g.y), Double(g.z)]))
        previousSequence = packet.sequence
        lastReceived = receivedAt
        samples.removeAll { packet.uptimeMilliseconds &- $0.time > 200 }
        guard samples.count >= 4, packet.uptimeMilliseconds &- samples[0].time >= 140 else {
            label = nil
            return
        }
        votes.append(tree.predict(features: GestureTree.features(samples.map(\.values))))
        if votes.count > 5 { votes.removeFirst() }
        // Counter.most_common breaks ties by first occurrence, as does this loop.
        var winner = votes[0]
        var best = 0
        for candidate in votes {
            let count = votes.filter { $0 == candidate }.count
            if count > best { winner = candidate; best = count }
        }
        label = winner
    }

    func currentLabel(at now: TimeInterval) -> String? {
        guard let lastReceived, now >= lastReceived, now-lastReceived <= 0.25 else { return nil }
        return label
    }
}

nonisolated enum BeatPlaybackPolicy {
    static func rejection(strength: UInt8, threshold: Int, mode: BeatFilterMode, label: String?) -> String? {
        if Int(strength) <= threshold { return "Below strength cutoff" }
        if mode == .gesture {
            guard let label else { return "Waiting for fresh motion" }
            if label == "idle" { return "Idle motion" }
        }
        return nil
    }
}
