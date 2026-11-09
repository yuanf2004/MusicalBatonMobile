import Foundation

@main
struct IMURecorderChecks {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: "/tmp/musical-baton-recorder-\(UUID().uuidString)", isDirectory: true)
        let recorder = IMURecorder(directory: directory)
        let metadata = IMURecordingMetadata(deviceID: "test", deviceName: "Test Baton",
                                             serviceUUID: BatonMotionPacket.serviceUUID,
                                             characteristicUUID: BatonMotionPacket.characteristicUUID)
        let bytes = Data([1, 3, 1, 0, 100, 0, 0, 0, 232, 3, 0, 0, 0, 0, 123, 0, 0, 0, 0, 0])
        for duration in [0.0, -1, 601, Double.infinity] {
            do {
                try recorder.start(duration: duration, metadata: metadata)
                fatalError("Accepted invalid recording duration")
            } catch IMURecorder.RecordingError.invalidDuration {}
        }
        try recorder.start(duration: 30, metadata: metadata)
        precondition(recorder.isRecording)
        recorder.receive(bytes)
        recorder.receive(bytes) // Duplicate reads remain separate received rows.
        precondition(recorder.progress.rows == 2)
        recorder.stop(reason: "Device disconnected")
        recorder.receive(bytes) // Late values must not enter a completed session.
        await waitForSave(recorder)
        precondition(!recorder.isRecording && !recorder.isFinishing)
        precondition(recorder.savedFiles.count == 1 && recorder.progress.rows == 2)
        precondition(recorder.completionMessage?.contains("Device disconnected") == true)
        let firstURL = recorder.savedFiles[0]
        let firstCSV = try String(contentsOf: firstURL, encoding: .utf8)
        precondition(firstCSV.components(separatedBy: "\r\n").count == 4) // Header + 2 rows + trailing empty.

        try recorder.start(duration: 1, metadata: metadata)
        recorder.receive(bytes)
        try await Task.sleep(for: .milliseconds(1100))
        recorder.receive(bytes)
        await waitForSave(recorder)
        precondition(!recorder.isRecording && recorder.savedFiles.count == 2)
        precondition(recorder.progress.rows == 1 && recorder.completionMessage?.contains("Duration reached") == true)
        let unchangedFirstCSV = try String(contentsOf: firstURL, encoding: .utf8)
        precondition(unchangedFirstCSV == firstCSV)
        let reloaded = IMURecorder(directory: directory)
        precondition(reloaded.savedFiles.count == 2)
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("regular file".utf8).write(to: blocker)
        let brokenRecorder = IMURecorder(directory: blocker.appendingPathComponent("recordings"))
        do {
            try brokenRecorder.start(duration: 1, metadata: metadata)
            fatalError("Recording accepted an unwritable destination")
        } catch {
            precondition(brokenRecorder.errorMessage != nil)
            precondition(!brokenRecorder.isRecording && !brokenRecorder.isFinishing)
        }
        print("Recorder duration validation, manual/timed stop, finalization, late-row exclusion, and saved-file persistence checks passed.")
    }

    @MainActor
    private static func waitForSave(_ recorder: IMURecorder) async {
        for _ in 0..<200 {
            if !recorder.isFinishing { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Recording did not finish")
    }
}
