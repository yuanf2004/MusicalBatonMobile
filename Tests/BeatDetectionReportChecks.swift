import Foundation

@main
struct BeatDetectionReportChecks {
    static func main() {
        func beat(_ ms: Int64, measure: Bool = false) -> RecordedBeat {
            RecordedBeat(elapsedMicroseconds: ms * 1000, isNewMeasure: measure)
        }
        // Played: 20 (20 late), 510 (10 late), 540 (double fire), 1500 (stray). Nothing near 1000 or 2000.
        let originals = [beat(20), beat(510), beat(540), beat(1500)]
        var finals = [originals[0], originals[1]]
        finals[0].elapsedMicroseconds = 0
        finals[1].elapsedMicroseconds = 500
        finals.append(beat(1000)); finals.append(beat(2000))
        var recording = ConductingRecording(name: "Test", originalSound: .click, currentSound: .click,
                                            originalBeats: originals, beats: finals)
        recording.recalculateBeatPositions()
        precondition(recording.hasBeatEdits)

        let r = BeatDetectionReport(recording: recording)
        precondition(r.matched == 2 && r.missed == 2 && r.falsePositives == 2)
        precondition(r.precision == 50 && r.recall == 50)
        precondition(r.netCountChange == 0 && r.netCountChangePercent == 0)
        precondition(abs(r.averageOffsetMagnitudeMilliseconds! - 15) < 1e-9)
        precondition(r.withinTolerancePercent == 100)
        precondition(r.beatsAdded == 2 && r.beatsDeleted == 2)
        precondition(r.labeled.count == originals.count + finals.count)
        let csv = r.csv().split(separator: "\n")
        precondition(csv.first == "time_s,source,label,offset_ms" && csv.count == 1 + r.labeled.count)
        precondition(csv.contains("0.020000,original,matched,20.000"))
        precondition(csv.contains("1.500000,original,false_positive,"))
        precondition(csv.contains("2.000000,final,missed,"))

        // Added beats never count toward precision; they only lower recall.
        var added = ConductingRecording(name: "A", originalSound: .click, currentSound: .click,
                                        originalBeats: [beat(0), beat(500)], beats: [])
        added.beats = added.originalBeats + [beat(1000), beat(1500)]
        let a = BeatDetectionReport(recording: added)
        precondition(a.precision == 100 && a.recall == 50 && a.netCountChange == 2)

        // Matching is by time, not identity: a played beat dragged 400 ms away is not a match.
        var dragged = ConductingRecording(name: "D", originalSound: .click, currentSound: .click,
                                          originalBeats: [beat(0)], beats: [])
        dragged.beats = dragged.originalBeats; dragged.beats[0].elapsedMicroseconds = 400_000
        let d = BeatDetectionReport(recording: dragged)
        precondition(d.matched == 0 && d.precision == 0 && d.recall == 0)

        // Negative offsets (early) count by magnitude.
        var early = ConductingRecording(name: "E", originalSound: .click, currentSound: .click,
                                        originalBeats: [beat(0), beat(500)], beats: [beat(30), beat(500)])
        early.beats[1] = early.originalBeats[1]
        precondition(abs(BeatDetectionReport(recording: early).averageOffsetMagnitudeMilliseconds! - 15) < 1e-9)

        let empty = BeatDetectionReport(recording: ConductingRecording(name: "Z", originalSound: .click, currentSound: .click, originalBeats: [], beats: []))
        precondition(empty.precision == nil && empty.recall == nil && empty.averageOffsetMagnitudeMilliseconds == nil)
        print("Beat detection report checks passed")
    }
}
