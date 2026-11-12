import Foundation
import Observation

nonisolated struct RecordedBeat: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var elapsedMicroseconds: Int64
    var isNewMeasure = false
    var isOriginal = true
    var isModified = false
    var measureNumber: Int?
    var isAccented = false

    var elapsedSeconds: TimeInterval { Double(elapsedMicroseconds) / 1_000_000 }
}

nonisolated struct ConductingRecording: Codable, Identifiable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var originalSound: ClickVoice
    var currentSound: ClickVoice
    var originalBeats: [RecordedBeat]
    var beats: [RecordedBeat]

    var duration: TimeInterval { (beats.map(\.elapsedSeconds).max() ?? 0) + (beats.isEmpty ? 0 : 0.06) }
    var isNameValid: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 80
    }
}

private nonisolated struct RecordingDraft: Codable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var sound: ClickVoice
    var beats: [RecordedBeat] = []
}

private nonisolated final class RecordingDiskWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MusicalBaton.recordings", qos: .utility)

    func write<T: Encodable & Sendable>(_ value: T, to url: URL) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        }
    }

    func writeDraft<T: Encodable & Sendable>(_ value: T, to url: URL,
                                             completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(value).write(to: url, options: .atomic)
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }

    func remove(_ url: URL) {
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
}

@MainActor
@Observable
final class ConductingRecordingStore {
    private(set) var recordings: [ConductingRecording] = []
    private(set) var activeDraftBeatCount = 0
    private(set) var recoveredDraft: ConductingRecording?
    private(set) var errorMessage: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let recordingsURL: URL
    @ObservationIgnored private let draftURL: URL
    @ObservationIgnored private let writer = RecordingDiskWriter()
    @ObservationIgnored private var draft: RecordingDraft?
    @ObservationIgnored private var recordingStartedUptime: TimeInterval?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConductingRecordings", isDirectory: true)
        self.directory = base
        recordingsURL = base.appendingPathComponent("recordings-v1.json")
        draftURL = base.appendingPathComponent("active-draft-v1.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if FileManager.default.fileExists(atPath: recordingsURL.path) {
                recordings = try decoder.decode([ConductingRecording].self, from: Data(contentsOf: recordingsURL))
                    .sorted { $0.modifiedAt > $1.modifiedAt }
            }
            if FileManager.default.fileExists(atPath: draftURL.path) {
                let found = try decoder.decode(RecordingDraft.self, from: Data(contentsOf: draftURL))
                draft = found
                activeDraftBeatCount = found.beats.count
                recoveredDraft = recording(from: found, name: "Recovered session")
            }
        } catch {
            errorMessage = "Could not load recordings: \(error.localizedDescription)"
        }
    }

    var isCapturing: Bool { draft != nil && recoveredDraft == nil }

    func beginCapture(sound: ClickVoice, startedAt uptime: TimeInterval) {
        guard draft == nil else { return }
        let value = RecordingDraft(sound: sound)
        draft = value
        recordingStartedUptime = uptime
        activeDraftBeatCount = 0
        persistDraft(value)
    }

    func captureAudibleBeat(at uptime: TimeInterval) {
        guard var value = draft, recoveredDraft == nil, let started = recordingStartedUptime else { return }
        let elapsed = Int64(max(0, uptime - started) * 1_000_000)
        value.beats.append(RecordedBeat(elapsedMicroseconds: elapsed))
        draft = value
        activeDraftBeatCount = value.beats.count
        persistDraft(value)
    }

    @discardableResult
    func finishCapture() -> ConductingRecording? {
        recordingStartedUptime = nil
        guard let draft else { return nil }
        guard !draft.beats.isEmpty else { discardDraft(); return nil }
        let value = recording(from: draft, name: defaultName(for: draft.createdAt))
        recoveredDraft = value
        return value
    }

    func saveDraft(named name: String) -> Bool {
        guard var value = recoveredDraft else { return false }
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isNameValid else { return false }
        value.modifiedAt = Date()
        guard update(value) else { return false }
        clearDraftState()
        return true
    }

    func postponeRecoveredDraft() {
        recordingStartedUptime = nil
    }

    func discardDraft() {
        clearDraftState()
    }

    @discardableResult
    func update(_ recording: ConductingRecording) -> Bool {
        var value = recording
        guard value.isNameValid else {
            errorMessage = "Use a recording name between 1 and 80 characters."
            return false
        }
        value.modifiedAt = Date()
        var next = recordings.filter { $0.id != value.id }
        next.append(value)
        next.sort { $0.modifiedAt > $1.modifiedAt }
        return persistRecordings(next)
    }

    func delete(ids: Set<UUID>) {
        _ = persistRecordings(recordings.filter { !ids.contains($0.id) })
    }

    private func recording(from draft: RecordingDraft, name: String) -> ConductingRecording {
        ConductingRecording(id: draft.id, name: name, createdAt: draft.createdAt, modifiedAt: Date(),
                            originalSound: draft.sound, currentSound: draft.sound,
                            originalBeats: draft.beats, beats: draft.beats)
    }

    private func clearDraftState() {
        draft = nil
        recoveredDraft = nil
        recordingStartedUptime = nil
        activeDraftBeatCount = 0
        writer.remove(draftURL)
    }

    private func persistDraft(_ value: RecordingDraft) {
        writer.writeDraft(value, to: draftURL) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.errorMessage = "Could not save recovery data: \(error)"
            }
        }
    }

    private func persistRecordings(_ next: [ConductingRecording]) -> Bool {
        do {
            try writer.write(next, to: recordingsURL)
            recordings = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save recordings: \(error.localizedDescription)"
            return false
        }
    }

    private func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Session \(formatter.string(from: date))"
    }
}

nonisolated enum RecordingAudioExporter {
    enum ExportError: LocalizedError {
        case tooLong
        var errorDescription: String? { "This recording is too long for this WAV export." }
    }

    static func wavData(for recording: ConductingRecording) throws -> Data {
        guard recording.duration.isFinite, recording.duration <= 60,
              recording.beats.allSatisfy({ $0.elapsedMicroseconds >= 0 }) else { throw ExportError.tooLong }
        let rate = 44_100
        let tailFrames = Int(Double(rate) * 0.06)
        let lastFrame = recording.beats.map { Int($0.elapsedSeconds * Double(rate)) }.max() ?? 0
        var samples = [Double](repeating: 0, count: max(1, lastFrame + tailFrames))
        let normal = pcmSamples(voice: recording.currentSound, accented: false)
        let accented = pcmSamples(voice: recording.currentSound, accented: true)
        for beat in recording.beats {
            let source = beat.isAccented || beat.isNewMeasure ? accented : normal
            let offset = max(0, Int(beat.elapsedSeconds * Double(rate)))
            for index in source.indices where offset + index < samples.count {
                samples[offset + index] += source[index]
            }
        }
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * 32767)
            append(UInt16(bitPattern: value), to: &pcm)
        }
        var result = Data()
        result.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &result)
        result.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &result); append(UInt16(1), to: &result); append(UInt16(1), to: &result)
        append(UInt32(rate), to: &result); append(UInt32(rate * 2), to: &result)
        append(UInt16(2), to: &result); append(UInt16(16), to: &result)
        result.append(contentsOf: "data".utf8); append(UInt32(pcm.count), to: &result); result.append(pcm)
        return result
    }

    static func writeTemporaryWAV(for recording: ConductingRecording) throws -> URL {
        let safe = recording.name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).prefix(50)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Musical Baton" : String(safe))-\(recording.id.uuidString.prefix(8)).wav")
        let rate = 44_100
        guard recording.duration.isFinite, recording.duration >= 0,
              recording.duration * Double(rate) * 2 < Double(UInt32.max - 36),
              recording.beats.allSatisfy({ $0.elapsedMicroseconds >= 0 }) else { throw ExportError.tooLong }
        let frames = max(1, Int((recording.beats.map(\.elapsedSeconds).max() ?? 0) * Double(rate)) + Int(Double(rate) * 0.06))
        let normal = pcmSamples(voice: recording.currentSound, accented: false)
        let accent = pcmSamples(voice: recording.currentSound, accented: true)
        let beats = recording.beats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = try FileHandle(forWritingTo: temporary)
        do {
            var header = Data("RIFF".utf8)
            append(UInt32(36 + frames * 2), to: &header)
            header.append(contentsOf: "WAVEfmt ".utf8)
            append(UInt32(16), to: &header); append(UInt16(1), to: &header); append(UInt16(1), to: &header)
            append(UInt32(rate), to: &header); append(UInt32(rate * 2), to: &header)
            append(UInt16(2), to: &header); append(UInt16(16), to: &header)
            header.append(contentsOf: "data".utf8); append(UInt32(frames * 2), to: &header)
            try file.write(contentsOf: header)
            var first = 0
            for start in stride(from: 0, to: frames, by: 4096) {
                let end = min(frames, start + 4096)
                var samples = [Double](repeating: 0, count: end - start)
                while first < beats.count {
                    let beat = beats[first]
                    let source = beat.isAccented || beat.isNewMeasure ? accent : normal
                    if Int(beat.elapsedSeconds * Double(rate)) + source.count > start { break }
                    first += 1
                }
                var index = first
                while index < beats.count {
                    let beat = beats[index]
                    let offset = Int(beat.elapsedSeconds * Double(rate))
                    if offset >= end { break }
                    let source = beat.isAccented || beat.isNewMeasure ? accent : normal
                    let lower = max(start, offset)
                    let upper = min(end, offset + source.count)
                    if lower < upper {
                        for frame in lower..<upper { samples[frame - start] += source[frame - offset] }
                    }
                    index += 1
                }
                var pcm = Data(capacity: samples.count * 2)
                for sample in samples { append(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32767)), to: &pcm) }
                try file.write(contentsOf: pcm)
            }
            try file.close()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch {
            try? file.close()
            throw error
        }
        return url
    }

    private static func pcmSamples(voice: ClickVoice, accented: Bool) -> [Double] {
        let data = Array(BeatSound.wavData(voice: voice, accented: accented).dropFirst(44))
        return stride(from: 0, to: data.count - 1, by: 2).map {
            let bits = UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8
            return Double(Int16(bitPattern: bits)) / 32768
        }
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    private static func append(_ value: UInt32, to data: inout Data) {
        append(UInt16(truncatingIfNeeded: value), to: &data)
        append(UInt16(truncatingIfNeeded: value >> 16), to: &data)
    }
}
