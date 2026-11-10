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

    func write<T: Encodable & Sendable>(_ value: T, to url: URL) {
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
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
        recordings.removeAll { $0.id == value.id }
        recordings.insert(value, at: 0)
        persistRecordings()
        clearDraftState()
        return true
    }

    func postponeRecoveredDraft() {
        recordingStartedUptime = nil
    }

    func discardDraft() {
        clearDraftState()
    }

    func update(_ recording: ConductingRecording) {
        var value = recording
        value.modifiedAt = Date()
        recordings.removeAll { $0.id == value.id }
        recordings.append(value)
        recordings.sort { $0.modifiedAt > $1.modifiedAt }
        persistRecordings()
    }

    func delete(ids: Set<UUID>) {
        recordings.removeAll { ids.contains($0.id) }
        persistRecordings()
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
        writer.write(value, to: draftURL)
    }

    private func persistRecordings() {
        writer.write(recordings, to: recordingsURL)
    }

    private func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Session \(formatter.string(from: date))"
    }
}

nonisolated enum RecordingAudioExporter {
    static func wavData(for recording: ConductingRecording) -> Data {
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
        try wavData(for: recording).write(to: url, options: .atomic)
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
