import Foundation

/// Compares the beats the baton played (originals) against the user's edited
/// beats (finals, treated as ground truth). Times are relative to recording start.
nonisolated struct BeatDetectionReport: Sendable {
    /// Half the 250 ms debounce; under half a beat even at 184 bpm (~326 ms).
    static let matchWindowMicroseconds: Int64 = 125_000
    /// Tied to the 50 ms audio lag requirement.
    static let timingToleranceMicroseconds: Int64 = 50_000

    enum Label: String, Sendable, CaseIterable {
        /// Played beat within the window of a final beat (true positive).
        case matched
        /// Final beat the baton never played (false negative).
        case missed
        /// Played beat with no final beat within the window (false positive).
        case falsePositive = "false_positive"
    }

    enum Source: String, Sendable { case original, final }

    struct LabeledBeat: Sendable, Equatable {
        var source: Source
        var elapsedMicroseconds: Int64
        var label: Label
        /// Original minus final for matched beats.
        var offsetMicroseconds: Int64?
    }

    let recordingName: String
    let recordingDate: Date
    let duration: TimeInterval
    let originalCount: Int
    let finalCount: Int
    let labeled: [LabeledBeat]
    let matched: Int, missed: Int, falsePositives: Int
    let offsetsMicroseconds: [Int64]
    let beatsAdded: Int, beatsDeleted: Int

    init(recording: ConductingRecording) {
        recordingName = recording.name
        recordingDate = recording.createdAt
        duration = recording.duration
        let originals = recording.originalBeats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
        let finals = recording.beats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
        originalCount = originals.count
        finalCount = finals.count

        // Match by time: every original/final pair within the window, closest first.
        // Beat identity is ignored, so dragging a beat far away or re-adding one nearby
        // is judged by where the baton fired, not by which dot the user edited.
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

        var beats: [LabeledBeat] = []
        var offsets: [Int64] = []
        for (o, beat) in originals.enumerated() {
            if let f = pairOfOriginal[o] {
                let offset = beat.elapsedMicroseconds - finals[f].elapsedMicroseconds
                offsets.append(offset)
                beats.append(.init(source: .original, elapsedMicroseconds: beat.elapsedMicroseconds, label: .matched, offsetMicroseconds: offset))
            } else {
                beats.append(.init(source: .original, elapsedMicroseconds: beat.elapsedMicroseconds, label: .falsePositive))
            }
        }
        for (f, beat) in finals.enumerated() {
            let offset = pairOfFinal[f].map { originals[$0].elapsedMicroseconds - beat.elapsedMicroseconds }
            beats.append(.init(source: .final, elapsedMicroseconds: beat.elapsedMicroseconds,
                               label: offset == nil ? .missed : .matched, offsetMicroseconds: offset))
        }
        labeled = beats.sorted { ($0.elapsedMicroseconds, $0.source == .original ? 0 : 1) < ($1.elapsedMicroseconds, $1.source == .original ? 0 : 1) }
        matched = offsets.count
        missed = finals.count - offsets.count
        falsePositives = originals.count - offsets.count
        offsetsMicroseconds = offsets

        let originalIDs = Set(originals.map(\.id)), finalIDs = Set(finals.map(\.id))
        beatsAdded = finalIDs.subtracting(originalIDs).count
        beatsDeleted = originalIDs.subtracting(finalIDs).count
    }

    // MARK: Beat detection (percentages; nil when the denominator is zero)

    /// Of the beats the baton played, the share that were real beats: TP ÷ (TP + FP).
    /// Beats added in the editor are not played beats, so they never raise precision.
    var precision: Double? { Self.percent(matched, originalCount) }
    /// Of the real (final) beats, the share the baton played: TP ÷ (TP + FN).
    var recall: Double? { Self.percent(matched, finalCount) }
    /// Final minus played; positive means the baton played too few beats.
    var netCountChange: Int { finalCount - originalCount }
    var netCountChangePercent: Double? {
        finalCount > 0 ? Double(netCountChange) / Double(finalCount) * 100 : nil
    }

    // MARK: Timing (matched beats only, milliseconds)

    var averageOffsetMagnitudeMilliseconds: Double? {
        offsetsMicroseconds.isEmpty ? nil : Double(offsetsMicroseconds.map { abs($0) }.reduce(0, +)) / Double(offsetsMicroseconds.count) / 1000
    }
    var withinTolerancePercent: Double? {
        Self.percent(offsetsMicroseconds.filter { abs($0) <= Self.timingToleranceMicroseconds }.count, offsetsMicroseconds.count)
    }

    // MARK: CSV

    /// One row per beat: relative time, source, label and offset (matched beats only).
    func csv() -> String {
        var lines = ["time_s,source,label,offset_ms"]
        for beat in labeled {
            lines.append([
                String(format: "%.6f", Double(beat.elapsedMicroseconds) / 1_000_000),
                beat.source.rawValue,
                beat.label.rawValue,
                beat.offsetMicroseconds.map { String(format: "%.3f", Double($0) / 1000) } ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func safeFileStem(_ name: String) -> String {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).prefix(50)
        return safe.isEmpty ? "Musical Baton" : String(safe)
    }

    static func percent(_ part: Int, _ whole: Int) -> Double? { whole > 0 ? Double(part) / Double(whole) * 100 : nil }
}
