import AVFoundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class RecordingPlaybackController {
    private(set) var playingID: UUID?
    private(set) var position: TimeInterval = 0
    private var engine: BeatAudioEngine?
    private var task: Task<Void, Never>?
    private var startedUptime: TimeInterval = 0
    private var recording: ConductingRecording?

    func toggle(_ value: ConductingRecording) {
        if playingID == value.id { pause(); return }
        stop()
        recording = value
        playingID = value.id
        start(from: 0)
    }

    func pause() {
        guard playingID != nil else { return }
        position += max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        task?.cancel(); task = nil
        engine?.stop(); engine = nil
        playingID = nil
    }

    func resume(_ value: ConductingRecording) {
        guard recording?.id == value.id, position < value.duration else { toggle(value); return }
        playingID = value.id
        start(from: position)
    }

    func stop() {
        task?.cancel(); task = nil
        engine?.stop(); engine = nil
        playingID = nil
        recording = nil
        position = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start(from offset: TimeInterval) {
        guard let recording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try BeatAudioEngine(voice: recording.currentSound)
            try player.start()
            engine = player
            startedUptime = ProcessInfo.processInfo.systemUptime
            task = Task { [weak self] in
                let remaining = recording.beats.filter { $0.elapsedSeconds >= offset }.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }
                var last = offset
                for beat in remaining {
                    do { try await Task.sleep(for: .seconds(max(0, beat.elapsedSeconds - last))) } catch { return }
                    guard let self, self.playingID == recording.id else { return }
                    _ = self.engine?.trigger(accented: beat.isAccented || beat.isNewMeasure)
                    last = beat.elapsedSeconds
                }
                do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
                self?.stop()
            }
        } catch { stop() }
    }
}

struct RecordingsView: View {
    let store: ConductingRecordingStore
    @State private var search = ""
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var confirmingDelete = false
    @State private var playback = RecordingPlaybackController()
    @State private var exportItem: ExportItem?
    @State private var exportError: String?
    @State private var exportingID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [ConductingRecording] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? store.recordings : store.recordings.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            if let recovered = store.recoveredDraft {
                Section("Needs attention") {
                    NavigationLink { RecordingSaveView(store: store, recording: recovered) } label: {
                        Label("Recovered session (\(recovered.beats.count) beats)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                }
            }
            Section {
                NavigationLink { TouchpadRecordingView(store: store) } label: {
                    Label("Create touchpad recording", systemImage: "hand.tap")
                }
            }
            Section("Saved recordings") {
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No recordings yet" : "No matching recordings",
                                           systemImage: search.isEmpty ? "waveform" : "magnifyingglass",
                                           description: Text(search.isEmpty ? "Record a conducting session or create one with the touchpad." : "Try a different name."))
                }
                ForEach(filtered) { recording in
                    HStack(spacing: 12) {
                        if selecting {
                            Button { toggleSelection(recording.id) } label: {
                                Image(systemName: selected.contains(recording.id) ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.plain).accessibilityLabel(selected.contains(recording.id) ? "Deselect \(recording.name)" : "Select \(recording.name)")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recording.name).font(.headline)
                            Text(recording.modifiedAt, format: .dateTime.month().day().year().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(recording.beats.count) beats · \(duration(recording.duration))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if playback.playingID == recording.id { playback.pause() }
                            else if playback.position > 0 { playback.resume(recording) }
                            else { playback.toggle(recording) }
                        } label: { Image(systemName: playback.playingID == recording.id ? "pause.fill" : "play.fill") }
                        .buttonStyle(.borderless).accessibilityLabel(playback.playingID == recording.id ? "Pause \(recording.name)" : "Play \(recording.name)")
                        NavigationLink { RecordingEditorView(store: store, recording: recording) } label: {
                            Image(systemName: "pencil")
                        }.accessibilityLabel("Edit \(recording.name)")
                        Button { export(recording) } label: {
                            if exportingID == recording.id { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                        }
                            .buttonStyle(.borderless).accessibilityLabel("Export \(recording.name) as audio")
                            .disabled(exportingID != nil)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if selecting { toggleSelection(recording.id) } }
                }
            }
        }
        .searchable(text: $search, prompt: "Search recording names")
        .batonPage("Recordings")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selecting {
                    Button("Delete", role: .destructive) { confirmingDelete = true }.disabled(selected.isEmpty)
                    Button("Done") { selecting = false; selected.removeAll() }
                } else if !store.recordings.isEmpty {
                    Button("Select") { selecting = true }
                }
            }
        }
        .confirmationDialog("Delete \(selected.count) recording\(selected.count == 1 ? "" : "s")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(ids: selected); selected.removeAll(); selecting = false }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
        .sheet(item: $exportItem) { item in ActivityView(items: [item.url]) }
        .alert("Could not export audio", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop() } }
        .onDisappear { playback.stop() }
    }

    private func toggleSelection(_ id: UUID) { if !selected.insert(id).inserted { selected.remove(id) } }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func export(_ recording: ConductingRecording) {
        exportingID = recording.id
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try RecordingAudioExporter.writeTemporaryWAV(for: recording)
                }.value
                exportItem = ExportItem(url: url)
            } catch { exportError = error.localizedDescription }
            exportingID = nil
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ExportItem: Identifiable { let id = UUID(); let url: URL }

struct RecordingSaveView: View {
    let store: ConductingRecordingStore
    let recording: ConductingRecording
    @State private var name: String
    @State private var confirmingDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(store: ConductingRecordingStore, recording: ConductingRecording) {
        self.store = store; self.recording = recording; _name = State(initialValue: recording.name)
    }

    var body: some View {
        Form {
            Section("Recording") {
                TextField("Recording name", text: $name)
                LabeledContent("Beats", value: "\(recording.beats.count)")
                LabeledContent("Duration", value: String(format: "%.1f seconds", recording.duration))
            }
            Section {
                Button("Save recording") { if store.saveDraft(named: name) { dismiss() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                Button("Discard recording", role: .destructive) { confirmingDiscard = true }
            }
        }.batonPage("Save recording")
        .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.discardDraft(); dismiss() }
            Button("Keep recording", role: .cancel) {}
        } message: { Text("Its beats have not been saved and this cannot be undone.") }
    }
}

struct TouchpadRecordingView: View {
    let store: ConductingRecordingStore
    @State private var beats: [RecordedBeat] = []
    @State private var started: ContinuousClock.Instant?
    @State private var sound: ClickVoice = .click
    @State private var showingSave = false
    @State private var confirmingExit = false
    @State private var name = "Touchpad recording"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(started == nil ? "Start with a new-measure beat" : "Tap in time").font(BatonTheme.serif(30, relativeTo: .title))
            Text("The first new-measure beat starts the timeline. It and later measure beats use a higher-pitched accent.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Picker("Sound", selection: $sound) { ForEach(ClickVoice.allCases) { Text($0.title).tag($0) } }
            HStack(spacing: 16) {
                Button("New measure beat", systemImage: "1.circle.fill") { addBeat(measure: true) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("New beat", systemImage: "circle.fill") { addBeat(measure: false) }
                    .buttonStyle(.bordered).controlSize(.large).disabled(started == nil)
            }
            Text("\(beats.count) beats").font(.title.monospacedDigit())
            Spacer()
            Button("Stop and save", systemImage: "stop.fill") { showingSave = true }.disabled(beats.isEmpty)
                .buttonStyle(.borderedProminent)
        }
        .padding(24).background(BatonTheme.canvas).navigationTitle("Touchpad recording")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { beats.isEmpty ? dismiss() : (confirmingExit = true) } } }
        .confirmationDialog("Discard this touchpad recording?", isPresented: $confirmingExit) {
            Button("Discard", role: .destructive) { dismiss() }; Button("Keep recording", role: .cancel) {}
        }
        .sheet(isPresented: $showingSave) {
            NavigationStack { Form { TextField("Recording name", text: $name); Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.batonPage("Save recording") }
        }
    }

    private func addBeat(measure: Bool) {
        let now = ContinuousClock.now
        if started == nil { guard measure else { return }; started = now }
        guard let started else { return }
        let elapsed = started.duration(to: now)
        let micros = Int64(elapsed.components.seconds) * 1_000_000 + Int64(elapsed.components.attoseconds / 1_000_000_000_000)
        beats.append(RecordedBeat(elapsedMicroseconds: max(0, micros), isNewMeasure: measure, isAccented: measure))
    }

    private func save() {
        let now = Date()
        let value = ConductingRecording(name: name.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now, modifiedAt: now,
                                        originalSound: sound, currentSound: sound, originalBeats: beats, beats: beats)
        store.update(value); showingSave = false; dismiss()
    }
}

struct RecordingEditorView: View {
    let store: ConductingRecordingStore
    let recording: ConductingRecording
    @State private var working: ConductingRecording
    @State private var undoStack: [ConductingRecording] = []
    @State private var redoStack: [ConductingRecording] = []
    @State private var selectedBeat: UUID?
    @State private var addingBeat = false
    @State private var addTime = 0.0
    @State private var editingName = false
    @Environment(\.dismiss) private var dismiss

    init(store: ConductingRecordingStore, recording: ConductingRecording) {
        self.store = store; self.recording = recording; _working = State(initialValue: recording)
    }

    var body: some View {
        Form {
            Section {
                if editingName {
                    TextField("Recording name", text: Binding(get: { working.name }, set: { value in mutate { $0.name = value } }))
                        .onSubmit { editingName = false }
                }
                else { Text(working.name).font(BatonTheme.serif(30, relativeTo: .title)).onTapGesture(count: 2) { editingName = true } }
                Button("Rename") { editingName = true }.font(.caption)
                Picker("Sound", selection: Binding(get: { working.currentSound }, set: { value in mutate { $0.currentSound = value } })) {
                    ForEach(ClickVoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Add beat mode", isOn: $addingBeat)
                if addingBeat {
                    HStack { TextField("Time", value: $addTime, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); Text("seconds"); Button("Add") { addBeat() } }
                    Text("Enter a position on the timeline, then add the beat.").font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo() }.disabled(undoStack.isEmpty)
                    Button("Redo", systemImage: "arrow.uturn.forward") { redo() }.disabled(redoStack.isEmpty)
                    Spacer(); Button("Revert beats & sound") { mutate { value in value.beats = value.originalBeats; value.currentSound = value.originalSound } }
                }
            }
            Section("Timeline") {
                RecordingTimeline(beats: working.beats, selectedBeat: selectedBeat, addingBeat: addingBeat) { id in
                    selectedBeat = id
                } addAt: { seconds in
                    mutate { $0.beats.append(RecordedBeat(elapsedMicroseconds: Int64(seconds * 1_000_000), isOriginal: false, isModified: true)) }
                }
                .frame(height: min(520, max(240, working.duration * 70)))
                .accessibilityLabel("Recording timeline")
                .accessibilityHint(addingBeat ? "Tap to add a beat at that time" : "Tap close to a beat to select it")
                ForEach(working.beats.sorted { $0.elapsedMicroseconds < $1.elapsedMicroseconds }) { beat in
                    Button { selectedBeat = beat.id } label: {
                        HStack {
                            Text(String(format: "%7.3f s", beat.elapsedSeconds)).monospacedDigit()
                            Image(systemName: beat.isNewMeasure ? "1.circle.fill" : (beat.isAccented ? "accent.diacritic" : "circle.fill"))
                            Text(beat.isNewMeasure ? "Measure beat" : (beat.isAccented ? "Accented beat" : "Beat"))
                            Spacer(); if selectedBeat == beat.id { Image(systemName: "checkmark") }
                        }
                    }.buttonStyle(.plain)
                }
            }
            if let selectedBeat, let beat = working.beats.first(where: { $0.id == selectedBeat }) {
                Section("Selected beat at \(String(format: "%.3f", beat.elapsedSeconds)) seconds") {
                    Toggle("Accent", isOn: Binding(get: { beat.isAccented }, set: { value in editBeat(selectedBeat) { $0.isAccented = value } }))
                    Toggle("Measure start", isOn: Binding(get: { beat.isNewMeasure }, set: { value in editBeat(selectedBeat) { $0.isNewMeasure = value; if value { $0.isAccented = true } } }))
                    HStack {
                        Button("Earlier", systemImage: "arrow.up") { shift(selectedBeat, by: -10_000) }
                        Button("Later", systemImage: "arrow.down") { shift(selectedBeat, by: 10_000) }
                    }
                    Button("Delete beat", role: .destructive) { mutate { $0.beats.removeAll { $0.id == selectedBeat } }; self.selectedBeat = nil }
                }
            }
        }
        .batonPage("Edit recording")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedBeat != nil {
                    Button(role: .destructive) { deleteSelectedBeat() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete selected beat")
                }
                Button("Save") { store.update(working); dismiss() }.disabled(!working.isNameValid)
            }
        }
    }

    private func mutate(_ change: (inout ConductingRecording) -> Void) {
        undoStack.append(working); redoStack.removeAll(); change(&working)
    }
    private func undo() { guard let value = undoStack.popLast() else { return }; redoStack.append(working); working = value }
    private func redo() { guard let value = redoStack.popLast() else { return }; undoStack.append(working); working = value }
    private func editBeat(_ id: UUID, change: (inout RecordedBeat) -> Void) {
        mutate { value in guard let index = value.beats.firstIndex(where: { $0.id == id }) else { return }; change(&value.beats[index]); value.beats[index].isModified = true }
    }
    private func shift(_ id: UUID, by amount: Int64) { editBeat(id) { $0.elapsedMicroseconds = max(0, $0.elapsedMicroseconds + amount) } }
    private func addBeat() {
        guard addTime.isFinite, addTime >= 0 else { return }
        mutate { $0.beats.append(RecordedBeat(elapsedMicroseconds: Int64(addTime * 1_000_000), isOriginal: false, isModified: true)) }
    }
    private func deleteSelectedBeat() {
        guard let selectedBeat else { return }
        mutate { $0.beats.removeAll { $0.id == selectedBeat } }
        self.selectedBeat = nil
    }
}

private struct RecordingTimeline: View {
    let beats: [RecordedBeat]
    let selectedBeat: UUID?
    let addingBeat: Bool
    let select: (UUID) -> Void
    let addAt: (TimeInterval) -> Void

    private var duration: TimeInterval { max(1, (beats.map(\.elapsedSeconds).max() ?? 0) + 0.25) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 64, y: 0)); path.addLine(to: CGPoint(x: 64, y: proxy.size.height))
                }.stroke(.secondary, lineWidth: 2)
                ForEach(0...Int(ceil(duration)), id: \.self) { second in
                    let y = CGFloat(Double(second) / duration) * proxy.size.height
                    Text("\(second)s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .position(x: 25, y: min(proxy.size.height - 7, max(7, y)))
                    Path { path in path.move(to: CGPoint(x: 55, y: y)); path.addLine(to: CGPoint(x: 73, y: y)) }
                        .stroke(.secondary.opacity(0.6), lineWidth: 1)
                }
                ForEach(beats) { beat in
                    let y = CGFloat(beat.elapsedSeconds / duration) * proxy.size.height
                    Button { select(beat.id) } label: {
                        Image(systemName: beat.isNewMeasure ? "1.circle.fill" : (beat.isAccented ? "circle.inset.filled" : "circle.fill"))
                            .font(.title3).foregroundStyle(selectedBeat == beat.id ? Color.orange : BatonTheme.ultramarine)
                            .frame(width: 48, height: 44)
                    }
                    .buttonStyle(.plain).position(x: 96, y: min(proxy.size.height - 12, max(12, y)))
                    .accessibilityLabel("\(beat.isNewMeasure ? "Measure" : beat.isAccented ? "Accented" : "Regular") beat at \(String(format: "%.3f", beat.elapsedSeconds)) seconds")
                }
                if addingBeat {
                    Text("Tap anywhere to add a beat").font(.caption).foregroundStyle(.secondary)
                        .padding(8).background(.thinMaterial, in: Capsule()).position(x: proxy.size.width / 2, y: 18)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                let seconds = max(0, min(duration, Double(event.location.y / proxy.size.height) * duration))
                if addingBeat { addAt(seconds) }
                else if let nearest = beats.min(by: { abs($0.elapsedSeconds - seconds) < abs($1.elapsedSeconds - seconds) }),
                        abs(nearest.elapsedSeconds - seconds) <= max(0.12, duration * 0.04) { select(nearest.id) }
            })
        }
        .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
