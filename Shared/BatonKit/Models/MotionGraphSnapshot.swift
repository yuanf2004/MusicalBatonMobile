import Foundation

/// Display-only data. Decimation never changes MotionHistory's recorded samples.
struct MotionGraphSnapshot {
    struct Point {
        let time: Double
        let value: Double
    }

    struct Trace: Identifiable {
        let channel: MotionChannel
        let segments: [[Point]]
        let yRange: ClosedRange<Double>
        let latestValue: Double?
        var id: MotionChannel { channel }
        var pointCount: Int { segments.reduce(0) { $0 + $1.count } }
    }

    var traces: [Trace] = []
    var latestPacket: BatonMotionPacket?
    var receivedCount: UInt64 = 0
    var intervalMilliseconds: UInt32?
    var clockResetCount: UInt64 = 0
    var parsingEnabled = false
    var errorMessage: String?

    init() {}

    init(history: MotionHistory, latestPacket: BatonMotionPacket?, parsingEnabled: Bool,
         errorMessage: String?, windowSeconds: Double) {
        self.latestPacket = latestPacket ?? history.samples.last?.packet
        receivedCount = history.receivedCount
        intervalMilliseconds = history.lastIntervalMilliseconds
        clockResetCount = history.clockResetCount
        self.parsingEnabled = parsingEnabled
        self.errorMessage = errorMessage
        let samples = history.visibleSamples(seconds: windowSeconds)
        let latestTime = Double(history.samples.last?.elapsedMilliseconds ?? 0) / 1000
        let prepared = MotionChannel.allCases.map { channel in
            (channel, Self.reduce(samples, channel: channel, latestTime: latestTime, windowSeconds: windowSeconds))
        }
        var accelExtent = 1000.0
        var gyroExtent = 10.0
        for (channel, segments) in prepared {
            let largest = segments.flatMap { $0 }.reduce(0.0) { max($0, abs($1.value)) } * 1.1
            if channel.isAcceleration { accelExtent = max(accelExtent, largest) }
            else { gyroExtent = max(gyroExtent, largest) }
        }
        traces = prepared.map { channel, segments in
            let extent = channel.isAcceleration ? accelExtent : gyroExtent
            return Trace(channel: channel, segments: segments, yRange: -extent...extent,
                         latestValue: self.latestPacket.flatMap { channel.value(in: $0) })
        }
    }

    private struct Candidate {
        let point: Point
        let segment: UInt64
    }

    private struct Bucket {
        let first: Int
        var last: Int
        var minimum: Int
        var maximum: Int
    }

    /// Keep first/min/max/last points in each of 64 time buckets (<=256 points).
    /// Selected points stay in source order and retain their continuous segment ID.
    private static func reduce(_ samples: [MotionHistory.Sample], channel: MotionChannel,
                               latestTime: Double, windowSeconds: Double) -> [[Point]] {
        let candidates = samples.compactMap { sample -> Candidate? in
            guard let value = channel.value(in: sample.packet) else { return nil }
            return Candidate(point: Point(time: Double(sample.elapsedMilliseconds) / 1000 - latestTime,
                                          value: value), segment: channel.segment(in: sample))
        }
        guard !candidates.isEmpty else { return [] }
        let bucketCount = 64
        var buckets = [Bucket?](repeating: nil, count: bucketCount)
        for (index, candidate) in candidates.enumerated() {
            let fraction = (candidate.point.time + windowSeconds) / max(windowSeconds, 0.001)
            let bucketIndex = min(bucketCount - 1, max(0, Int(fraction * Double(bucketCount))))
            if var bucket = buckets[bucketIndex] {
                bucket.last = index
                if candidate.point.value < candidates[bucket.minimum].point.value { bucket.minimum = index }
                if candidate.point.value > candidates[bucket.maximum].point.value { bucket.maximum = index }
                buckets[bucketIndex] = bucket
            } else {
                buckets[bucketIndex] = Bucket(first: index, last: index, minimum: index, maximum: index)
            }
        }
        var selected = Set<Int>()
        for bucket in buckets.compactMap({ $0 }) {
            selected.formUnion([bucket.first, bucket.minimum, bucket.maximum, bucket.last])
        }
        var segments: [[Point]] = []
        var previousSegment: UInt64?
        for index in selected.sorted() {
            let candidate = candidates[index]
            if previousSegment != candidate.segment { segments.append([]) }
            segments[segments.count - 1].append(candidate.point)
            previousSegment = candidate.segment
        }
        return segments
    }
}
