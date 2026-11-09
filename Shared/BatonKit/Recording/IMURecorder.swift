import Foundation
import Observation

@MainActor
@Observable
final class IMURecorder {
    private(set) var isRecording = false
    private(set) var isFinishing = false
    private(set) var savedFiles: [URL] = []
    private(set) var completionMessage: String?
    private(set) var errorMessage: String?
    private(set) var targetDuration = 30.0
    @ObservationIgnored var onEvent: ((String) -> Void)?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var writer: IMUCSVFileWriter?
    @ObservationIgnored private var metadata: IMURecordingMetadata?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var startedUptime = 0.0
    @ObservationIgnored private var stoppedElapsed = 0.0
    @ObservationIgnored private var receivedRows = 0

    struct Progress: Equatable {
        var rows = 0
        var elapsed = 0.0
        var remaining = 0.0
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IMURecordings", isDirectory: true)
        if FileManager.default.fileExists(atPath: self.directory.path) {
            do {
                savedFiles = try FileManager.default.contentsOfDirectory(at: self.directory,
                    includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    .filter { $0.pathExtension.lowercased() == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            } catch { errorMessage = "Could not list saved recordings: \(error.localizedDescription)" }
        }
    }

    var progress: Progress {
        let elapsed = isRecording ? max(0, ProcessInfo.processInfo.systemUptime - startedUptime) : stoppedElapsed
        return Progress(rows: receivedRows, elapsed: elapsed, remaining: max(0, targetDuration - elapsed))
    }

    func start(duration: TimeInterval, metadata: IMURecordingMetadata) throws {
        guard !isRecording, !isFinishing else { return }
        guard duration.isFinite, (1...600).contains(duration) else { throw RecordingError.invalidDuration }
        let id = UUID()
        let filenameFormatter = DateFormatter()
        filenameFormatter.locale = Locale(identifier: "en_US_POSIX")
        filenameFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        filenameFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("baton-imu-\(filenameFormatter.string(from: Date()))-\(id.uuidString.prefix(8)).csv")
        let newWriter: IMUCSVFileWriter
        do {
            newWriter = try IMUCSVFileWriter(url: url) { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id else { return }
                    self.errorMessage = "CSV write failed: \(message). The file may be incomplete."
                    self.stop(reason: "File write error")
                }
            }
        } catch {
            errorMessage = "Could not create CSV recording: \(error.localizedDescription)"
            throw error
        }
        sessionID = id
        writer = newWriter
        self.metadata = metadata
        targetDuration = duration
        startedUptime = ProcessInfo.processInfo.systemUptime
        stoppedElapsed = 0
        receivedRows = 0
        errorMessage = nil
        completionMessage = nil
        isRecording = true
        onEvent?("IMU recording started for \(Int(duration)) seconds")
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, self.sessionID == id else { return }
            self.stop(reason: "Duration reached")
        }
    }

    func receive(_ data: Data, at date: Date = Date(),
                 uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRecording, let writer, let metadata else { return }
        let elapsed = max(0, uptime - startedUptime)
        guard elapsed < targetDuration else { stop(reason: "Duration reached"); return }
        receivedRows += 1
        writer.append(IMUCSVRow(receivedAt: date, elapsedMilliseconds: elapsed * 1000,
                                metadata: metadata, data: data))
    }

    func stop(reason: String = "Stopped manually") {
        guard isRecording, let writer, let id = sessionID else { return }
        stoppedElapsed = max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        isRecording = false
        isFinishing = true
        deadlineTask?.cancel()
        deadlineTask = nil
        onEvent?("IMU recording stopped: \(reason). Saving CSV…")
        writer.finish { [weak self] summary in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == id else { return }
                self.writer = nil
                self.metadata = nil
                self.isFinishing = false
                self.receivedRows = summary.writtenRows
                self.savedFiles.insert(summary.url, at: 0)
                self.completionMessage = "\(reason). Saved \(summary.writtenRows) rows; \(summary.malformedRows) malformed packets."
                if let error = summary.errorMessage {
                    self.errorMessage = "CSV file may be incomplete: \(error)"
                }
                self.onEvent?("CSV saved: \(summary.url.lastPathComponent), \(summary.writtenRows) rows")
                if let error = summary.errorMessage { self.onEvent?("ERROR: CSV write: \(error)") }
            }
        }
    }

    enum RecordingError: LocalizedError {
        case invalidDuration
        var errorDescription: String? { "Choose a duration between 1 and 600 seconds." }
    }
}
