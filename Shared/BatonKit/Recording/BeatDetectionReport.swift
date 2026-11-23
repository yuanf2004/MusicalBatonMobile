import Foundation

/// Compares the beats the baton detected (originals) against the user's edited
/// beats (finals, treated as ground truth). Times are relative to recording start.
nonisolated struct BeatDetectionReport: Sendable {
    /// Half the 250 ms debounce; under half a beat even at 184 bpm (~326 ms).
    static let matchWindowMicroseconds: Int64 = 125_000
    /// Tied to the 50 ms audio lag requirement.
    static let timingToleranceMicroseconds: Int64 = 50_000

    enum Label: String, Sendable, CaseIterable {
        case matched, missed, duplicate, falseTrigger = "false_trigger"
        var title: String {
            switch self { case .matched: "Matched"; case .missed: "Missed"; case .duplicate: "Duplicate"; case .falseTrigger: "False trigger" }
        }
    }

    enum Source: String, Sendable { case original, final }

    struct LabeledBeat: Sendable, Equatable {
        var source: Source
        var elapsedMicroseconds: Int64
        var label: Label
        /// Original minus final for matched beats; positive means the baton was late.
        var offsetMicroseconds: Int64?
        var measureNumber: Int?
    }

    struct MeasureAccuracy: Sendable, Equatable {
        var measure: Int
        var matched = 0, missed = 0, duplicates = 0, falseTriggers = 0
        var accuracy: Double? { BeatDetectionReport.percent(matched, matched + missed + duplicates + falseTriggers) }
    }

    let recordingName: String
    let recordingDate: Date
    let duration: TimeInterval
    let sensitivity: DetectionSensitivity?
    let originalCount: Int
    let finalCount: Int
    let labeled: [LabeledBeat]
    let matched: Int, missed: Int, duplicates: Int, falseTriggers: Int
    let offsetsMicroseconds: [Int64]
    let measures: [MeasureAccuracy]
    let beatsAdded: Int, beatsDeleted: Int, undoCount: Int
    let originalIntervals: [Double], finalIntervals: [Double]

    init(recording: ConductingRecording) {
        recordingName = recording.name
        recordingDate = recording.createdAt
        duration = recording.duration
        sensitivity = recording.sensitivity
        let originals = recording.originalBeats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
        let finals = recording.beats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
        originalCount = originals.count
        finalCount = finals.count

        // Every original/final pair within the window, closest first; ties break by time.
        var candidates: [(distance: Int64, o: Int, f: Int)] = []
        var start = 0
        for (o, beat) in originals.enumerated() {
            while start < finals.count, finals[start].elapsedMicroseconds < beat.elapsedMicroseconds - Self.matchWindowMicroseconds { start += 1 }
            var f = start
            while f < finals.count, finals[f].elapsedMicroseconds <= beat.elapsedMicroseconds + Self.matchWindowMicroseconds {
                candidates.append((abs(beat.elapsedMicroseconds - finals[f].elapsedMicroseconds), o, f))
                f += 1
            }
        }
        candidates.sort { ($0.distance, $0.o, $0.f) < ($1.distance, $1.o, $1.f) }
        var pairOfOriginal = [Int?](repeating: nil, count: originals.count)
        var pairOfFinal = [Int?](repeating: nil, count: finals.count)
        for c in candidates where pairOfOriginal[c.o] == nil && pairOfFinal[c.f] == nil {
            pairOfOriginal[c.o] = c.f; pairOfFinal[c.f] = c.o
        }
        // An unpaired original near any matched final is a double fire.
        var nearMatchedFinal = [Int?](repeating: nil, count: originals.count)
        for c in candidates where pairOfOriginal[c.o] == nil && pairOfFinal[c.f] != nil && nearMatchedFinal[c.o] == nil {
            nearMatchedFinal[c.o] = c.f
        }

        func measure(near time: Int64) -> Int? {
            // Measure of the latest final beat at or before this time (else the first final beat).
            var lo = 0, hi = finals.count
            while lo < hi { let mid = (lo + hi) / 2; if finals[mid].elapsedMicroseconds <= time { lo = mid + 1 } else { hi = mid } }
            return finals.isEmpty ? nil : finals[max(0, lo - 1)].measureNumber
        }

        var beats: [LabeledBeat] = []
        var offsets: [Int64] = []
        var counts = (matched: 0, missed: 0, dup: 0, falseT: 0)
        for (o, beat) in originals.enumerated() {
            if let f = pairOfOriginal[o] {
                let offset = beat.elapsedMicroseconds - finals[f].elapsedMicroseconds
                offsets.append(offset); counts.matched += 1
                beats.append(.init(source: .original, elapsedMicroseconds: beat.elapsedMicroseconds, label: .matched,
                                   offsetMicroseconds: offset, measureNumber: finals[f].measureNumber))
            } else if let f = nearMatchedFinal[o] {
                counts.dup += 1
                beats.append(.init(source: .original, elapsedMicroseconds: beat.elapsedMicroseconds, label: .duplicate,
                                   measureNumber: finals[f].measureNumber))
            } else {
                counts.falseT += 1
                beats.append(.init(source: .original, elapsedMicroseconds: beat.elapsedMicroseconds, label: .falseTrigger,
                                   measureNumber: measure(near: beat.elapsedMicroseconds)))
            }
        }
        for (f, beat) in finals.enumerated() {
            if let o = pairOfFinal[f] {
                beats.append(.init(source: .final, elapsedMicroseconds: beat.elapsedMicroseconds, label: .matched,
                                   offsetMicroseconds: originals[o].elapsedMicroseconds - beat.elapsedMicroseconds,
                                   measureNumber: beat.measureNumber))
            } else {
                counts.missed += 1
                beats.append(.init(source: .final, elapsedMicroseconds: beat.elapsedMicroseconds, label: .missed,
                                   measureNumber: beat.measureNumber))
            }
        }
        labeled = beats.sorted { ($0.elapsedMicroseconds, $0.source == .original ? 0 : 1) < ($1.elapsedMicroseconds, $1.source == .original ? 0 : 1) }
        matched = counts.matched; missed = counts.missed; duplicates = counts.dup; falseTriggers = counts.falseT
        offsetsMicroseconds = offsets

        // Per-measure counts only when the user labeled measures. Matched pairs count once (from the original side).
        if finals.contains(where: \.isNewMeasure) {
            var table: [Int: MeasureAccuracy] = [:]
            for beat in beats {
                guard let m = beat.measureNumber else { continue }
                var row = table[m] ?? MeasureAccuracy(measure: m)
                switch (beat.source, beat.label) {
                case (.original, .matched): row.matched += 1
                case (_, .missed): row.missed += 1
                case (_, .duplicate): row.duplicates += 1
                case (_, .falseTrigger): row.falseTriggers += 1
                default: break
                }
                table[m] = row
            }
            measures = table.values.sorted { $0.measure < $1.measure }
        } else { measures = [] }

        let originalIDs = Set(originals.map(\.id)), finalIDs = Set(finals.map(\.id))
        beatsAdded = finalIDs.subtracting(originalIDs).count
        beatsDeleted = originalIDs.subtracting(finalIDs).count
        undoCount = recording.editLog?.undoCount ?? 0

        func intervals(_ list: [RecordedBeat]) -> [Double] {
            zip(list, list.dropFirst()).map { Double($1.elapsedMicroseconds - $0.elapsedMicroseconds) / 1_000_000 }.filter { $0 > 0 }
        }
        originalIntervals = intervals(originals)
        finalIntervals = intervals(finals)
    }

    // MARK: Beat detection (percentages; nil when the denominator is zero)

    var netCountDifference: Double? { Self.percent(abs(originalCount - finalCount), finalCount) }
    var missedPercent: Double? { Self.percent(missed, finalCount) }
    var duplicatePercent: Double? { Self.percent(duplicates, originalCount) }
    var falseTriggerPercent: Double? { Self.percent(falseTriggers, originalCount) }
    var beatAccuracy: Double? { Self.percent(matched, matched + missed + duplicates + falseTriggers) }

    // MARK: Timing (matched beats only, milliseconds)

    var averageOffsetMilliseconds: Double? {
        offsetsMicroseconds.isEmpty ? nil : Double(offsetsMicroseconds.reduce(0, +)) / Double(offsetsMicroseconds.count) / 1000
    }
    var timingConsistencyMilliseconds: Double? {
        Self.standardDeviation(offsetsMicroseconds.map { Double($0) / 1000 })
    }
    var withinTolerancePercent: Double? {
        Self.percent(offsetsMicroseconds.filter { abs($0) <= Self.timingToleranceMicroseconds }.count, offsetsMicroseconds.count)
    }

    // MARK: Tempo

    var originalTempo: Double? { Self.tempo(originalIntervals) }
    var finalTempo: Double? { Self.tempo(finalIntervals) }
    var tempoDifferencePercent: Double? {
        guard let o = originalTempo, let f = finalTempo, f > 0 else { return nil }
        return abs(o - f) / f * 100
    }
    /// Standard deviation of inter-beat intervals in milliseconds.
    var originalSteadinessMilliseconds: Double? { Self.standardDeviation(originalIntervals.map { $0 * 1000 }) }
    var finalSteadinessMilliseconds: Double? { Self.standardDeviation(finalIntervals.map { $0 * 1000 }) }

    // MARK: Edit effort

    var editRatePercent: Double? { Self.percent(beatsAdded + beatsDeleted, finalCount) }

    // MARK: CSV

    /// One row per beat: relative time, source, label and offset (matched beats only).
    func csv() -> String {
        var lines = ["time_s,source,label,offset_ms,measure"]
        for beat in labeled {
            lines.append([
                String(format: "%.6f", Double(beat.elapsedMicroseconds) / 1_000_000),
                beat.source.rawValue,
                beat.label.rawValue,
                beat.offsetMicroseconds.map { String(format: "%.3f", Double($0) / 1000) } ?? "",
                beat.measureNumber.map(String.init) ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func safeFileStem(_ name: String) -> String {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).prefix(50)
        return safe.isEmpty ? "Musical Baton" : String(safe)
    }

    // MARK: Helpers

    static func percent(_ part: Int, _ whole: Int) -> Double? { whole > 0 ? Double(part) / Double(whole) * 100 : nil }
    static func tempo(_ intervals: [Double]) -> Double? {
        intervals.isEmpty ? nil : 60 / (intervals.reduce(0, +) / Double(intervals.count))
    }
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}

