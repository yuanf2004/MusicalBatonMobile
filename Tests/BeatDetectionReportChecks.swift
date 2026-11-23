import Foundation

@main
struct BeatDetectionReportChecks {
    static func main() {
        func beat(_ ms: Int64, measure: Bool = false) -> RecordedBeat {
            RecordedBeat(elapsedMicroseconds: ms * 1000, isNewMeasure: measure)
        }
        // Detected: 0 (+20 late), 510 & 540 (double fire), 1500 (stray), nothing near 2000.
        let originals = [beat(20), beat(510), beat(540), beat(1500)]
        var finals = [originals[0], originals[1]]
        finals[0].elapsedMicroseconds = 0; finals[0].isNewMeasure = true
        finals[1].elapsedMicroseconds = 500
        finals.append(beat(1000)); finals.append(beat(2000, measure: true))
        var recording = ConductingRecording(name: "Test", originalSound: .click, currentSound: .click,
                                            originalBeats: originals, beats: finals)
        recording.editLog = RecordingEditLog(undoCount: 2)
        recording.recalculateBeatPositions()
        precondition(recording.hasBeatEdits)

        let r = BeatDetectionReport(recording: recording)
        precondition(r.matched == 2 && r.missed == 2 && r.duplicates == 1 && r.falseTriggers == 1)
        precondition(r.offsetsMicroseconds.sorted() == [10_000, 20_000])
        precondition(abs(r.beatAccuracy! - 100 * 2 / 6) < 1e-9)
        precondition(r.missedPercent == 50 && r.duplicatePercent == 25 && r.falseTriggerPercent == 25)
        precondition(r.netCountDifference == 0)
        precondition(abs(r.averageOffsetMilliseconds! - 15) < 1e-9)
        precondition(abs(r.timingConsistencyMilliseconds! - 5) < 1e-9)
        precondition(r.withinTolerancePercent == 100)
        precondition(r.beatsAdded == 2 && r.beatsDeleted == 2 && r.undoCount == 2 && r.editRatePercent == 100)
        precondition(abs(r.finalTempo! - 90) < 1e-9)
        precondition(r.measures.map(\.measure) == [1, 2])
        // Each beat appears once per source; matched pairs on both rows.
        precondition(r.labeled.count == originals.count + finals.count)
        let csv = r.csv().split(separator: "\n")
        precondition(csv.first == "time_s,source,label,offset_ms,measure" && csv.count == 1 + r.labeled.count)
        precondition(csv.contains("0.020000,original,matched,20.000,1"))
        precondition(csv.contains("1.500000,original,false_trigger,,1"))

        // Nearest pair wins, not first-in-time: 0 and 100 detected, edit kept only 100.
        var near = ConductingRecording(name: "N", originalSound: .click, currentSound: .click,
                                       originalBeats: [beat(0), beat(100)], beats: [])
        near.beats = [near.originalBeats[1]]
        let n = BeatDetectionReport(recording: near)
        precondition(n.matched == 1 && n.duplicates == 1 && n.offsetsMicroseconds == [0])

        // Unedited recordings are not reportable; empty lists have no percentages.
        let plain = ConductingRecording(name: "P", originalSound: .click, currentSound: .click, originalBeats: [beat(0)], beats: [beat(0)])
        var same = plain; same.beats = same.originalBeats
        precondition(!same.hasBeatEdits)
        let empty = BeatDetectionReport(recording: ConductingRecording(name: "E", originalSound: .click, currentSound: .click, originalBeats: [], beats: []))
        precondition(empty.beatAccuracy == nil && empty.averageOffsetMilliseconds == nil && empty.finalTempo == nil)
        print("Beat detection report checks passed")
    }
}
