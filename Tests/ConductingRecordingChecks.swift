import Foundation

@main
struct ConductingRecordingChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baton-recording-checks-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConductingRecordingStore(directory: directory)
        store.beginCapture(sound: .wood, startedAt: 100)
        store.captureAudibleBeat(at: 100.125)
        store.captureAudibleBeat(at: 100.625)
        let draft = store.finishCapture()
        precondition(draft?.beats.map(\.elapsedMicroseconds) == [125_000, 625_000])
        precondition(draft?.beats.allSatisfy { $0.isOriginal && !$0.isModified && !$0.isNewMeasure } == true)
        precondition(store.saveDraft(named: " Rehearsal "))
        precondition(store.recordings.first?.name == "Rehearsal")
        precondition(store.recordings.first?.originalSound == .wood)

        guard var edited = store.recordings.first else { preconditionFailure("Missing saved recording") }
        edited.currentSound = .bell
        edited.beats[0].isAccented = true
        edited.beats[0].isModified = true
        edited.beats.append(RecordedBeat(elapsedMicroseconds: 900_000, isOriginal: false, isModified: true))
        store.update(edited)
        let wav = try RecordingAudioExporter.wavData(for: edited)
        precondition(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        precondition(String(data: wav.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE")
        precondition(wav.count > 44)

        let exported = try RecordingAudioExporter.writeTemporaryWAV(for: edited)
        defer { try? FileManager.default.removeItem(at: exported) }
        let streamed = try Data(contentsOf: exported)
        precondition(streamed == wav)

        let reload = ConductingRecordingStore(directory: directory)
        precondition(reload.recordings.count == 1)
        precondition(reload.recordings[0].beats.count == 3)
        precondition(reload.recordings[0].originalBeats.count == 2)
        precondition(reload.recordings[0].currentSound == .bell)

        let recoveryDirectory = directory.appendingPathComponent("recovery", isDirectory: true)
        let recovery = ConductingRecordingStore(directory: recoveryDirectory)
        recovery.beginCapture(sound: .click, startedAt: 500)
        recovery.captureAudibleBeat(at: 500.25)
        Thread.sleep(forTimeInterval: 0.2)
        let recovered = ConductingRecordingStore(directory: recoveryDirectory)
        precondition(recovered.recoveredDraft?.beats.map(\.elapsedMicroseconds) == [250_000])
        let blocked = recoveryDirectory.appendingPathComponent("recordings-v1.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        precondition(!recovered.saveDraft(named: "Must survive"))
        precondition(recovered.recoveredDraft != nil && recovered.recordings.isEmpty)
        precondition(recovered.errorMessage != nil)
        let afterFailure = ConductingRecordingStore(directory: recoveryDirectory)
        precondition(FileManager.default.fileExists(atPath: recoveryDirectory.appendingPathComponent("active-draft-v1.json").path))
        _ = afterFailure
        try FileManager.default.removeItem(at: blocked)
        precondition(recovered.saveDraft(named: "Retry"))
        var long = edited
        long.beats = [RecordedBeat(elapsedMicroseconds: 61_000_000)]
        do { _ = try RecordingAudioExporter.wavData(for: long); preconditionFailure("Expected memory export limit") }
        catch RecordingAudioExporter.ExportError.tooLong {}
        let longURL = try RecordingAudioExporter.writeTemporaryWAV(for: long)
        defer { try? FileManager.default.removeItem(at: longURL) }
        let size = try FileManager.default.attributesOfItem(atPath: longURL.path)[.size] as! NSNumber
        precondition(size.intValue > 5_000_000)
        print("Conducting recording capture, original/edit separation, persistence, draft recovery and WAV export passed")
    }
}
