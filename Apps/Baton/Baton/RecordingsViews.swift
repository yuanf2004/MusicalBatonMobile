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

    var currentPosition: TimeInterval {
        position + (playingID == nil ? 0 : max(0, ProcessInfo.processInfo.systemUptime - startedUptime))
    }

    func toggle(_ value: ConductingRecording) {
        if playingID == value.id { pause(); return }
        stop()
        recording = value
        playingID = value.id
        start(from: 0)
    }

    func play(_ value: ConductingRecording, fromMeasure measure: Int) {
        guard let offset = value.beats.filter({ $0.measureNumber == measure }).map(\.elapsedSeconds).min() else { return }
        stop()
        recording = value
        playingID = value.id
        position = offset
        start(from: offset)
    }

    func seek(_ value: ConductingRecording, to seconds: TimeInterval) {
        pause()
        recording = value
        position = min(value.duration, max(0, seconds))
    }

    func pause() {
        guard playingID != nil else { return }
        position += max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        task?.cancel(); task = nil
        engine?.stop(); engine = nil
        playingID = nil
    }

    func resume(_ value: ConductingRecording) {
        guard recording?.id == value.id, position <= value.duration else { toggle(value); return }
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
                for beat in remaining {
                    do { try await Task.sleep(for: .seconds(max(0, beat.elapsedSeconds - offset - (ProcessInfo.processInfo.systemUptime - (self?.startedUptime ?? 0))))) } catch { return }
                    guard let self, self.playingID == recording.id else { return }
                    _ = self.engine?.trigger(accented: beat.isAccented || beat.isNewMeasure)
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
    @State private var singleDelete: ConductingRecording?
    @State private var showingGuide = false
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
                Section("Needs Attention") {
                    NavigationLink { RecordingSaveView(store: store, recording: recovered) } label: {
                        Label("Recovered session (\(recovered.beats.count) beats)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                }
            }
            Section {
                NavigationLink { TouchpadRecordingView(store: store) } label: {
                    Label("Create Touchpad Recording", systemImage: "hand.tap")
                }
            }
            Section("Saved Recordings") {
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No recordings yet" : "No matching recordings",
                                           systemImage: search.isEmpty ? "waveform" : "magnifyingglass",
                                           description: Text(search.isEmpty ? "Record a conducting session or create one with the touchpad." : "Try a different name."))
                }
                ForEach(filtered) { recording in
                    HStack(spacing: 12) {
                        if selecting {
                            Button { toggleSelection(recording.id) } label: {
                                Image(systemName: selected.contains(recording.id) ? "checkmark.square.fill" : "square")
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
                        if !measures(in: recording).isEmpty {
                            Menu {
                                ForEach(measures(in: recording), id: \.self) { measure in
                                    Button("Measure \(measure)") { playback.play(recording, fromMeasure: measure) }
                                }
                            } label: { Image(systemName: "text.line.first.and.arrowtriangle.forward") }
                            .accessibilityLabel("Play \(recording.name) from a measure")
                        }
                        NavigationLink { RecordingEditorView(store: store, recording: recording) } label: {
                            Image(systemName: "pencil")
                        }.accessibilityLabel("Edit \(recording.name)")
                        Button { export(recording) } label: {
                            if exportingID == recording.id { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                        }
                            .buttonStyle(.borderless).accessibilityLabel("Export \(recording.name) as audio")
                            .disabled(exportingID != nil)
                        Button(role: .destructive) { singleDelete = recording } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("Delete \(recording.name)")
                    }
                    .contentShape(Rectangle())
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
                Button { showingGuide = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("Recording guide")
            }
        }
        .confirmationDialog("Delete \(selected.count) recording\(selected.count == 1 ? "" : "s")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(ids: selected); selected.removeAll(); selecting = false }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
        .confirmationDialog("Delete \(singleDelete?.name ?? "this recording")?", isPresented: Binding(
            get: { singleDelete != nil }, set: { if !$0 { singleDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Recording", role: .destructive) {
                if let id = singleDelete?.id { store.delete(ids: Set([id])) }
                singleDelete = nil
            }
            Button("Cancel", role: .cancel) { singleDelete = nil }
        } message: { Text("This cannot be undone.") }
        .sheet(isPresented: $showingGuide) { NavigationStack { RecordingGuideView() } }
        .sheet(item: $exportItem) { item in ActivityView(items: [item.url]) }
        .alert("Could not export audio", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop() } }
        .onDisappear { playback.stop() }
    }

    private func toggleSelection(_ id: UUID) { if !selected.insert(id).inserted { selected.remove(id) } }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func measures(in recording: ConductingRecording) -> [Int] {
        Array(Set(recording.beats.compactMap(\.measureNumber))).sorted()
    }
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
                TextField("Recording Name", text: $name)
                LabeledContent("Beats", value: "\(recording.beats.count)")
                LabeledContent("Duration", value: String(format: "%.1f seconds", recording.duration))
            }
            Section {
                Button("Save Recording") { if store.saveDraft(named: name) { dismiss() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                Button("Discard Recording", role: .destructive) { confirmingDiscard = true }
            }
        }.batonPage("Save Recording")
        .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.discardDraft(); dismiss() }
            Button("Keep Recording", role: .cancel) {}
        } message: { Text("Its beats have not been saved and this cannot be undone.") }
    }
}

struct TouchpadRecordingView: View {
    let store: ConductingRecordingStore
    @State private var beats: [RecordedBeat] = []
    @State private var started: ContinuousClock.Instant?
    @State private var sound: ClickVoice = .click
    @State private var preview = SoundPreview()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSave = false
    @State private var confirmingExit = false
    @State private var name = "Touchpad Recording"
    @State private var startingMeasureText = ""
    @State private var currentMeasure: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text(started == nil ? "Start with a new-measure beat" : "Tap in time").font(BatonTheme.serif(30, relativeTo: .title))
                TermHelpButton(title: "New Measure Beat", message: "A new measure beat marks the first beat of a musical measure and plays with a higher-frequency accent.")
            }
            Text("The first new-measure beat starts the timeline. It and later measure beats use a higher-pitched accent.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Picker("Sound", selection: Binding(get: { sound }, set: { sound = $0; preview.play($0) })) { ForEach(ClickVoice.allCases) { Text($0.title.capitalized).tag($0) } }
            HStack {
                TextField("Starting Measure (optional)", text: $startingMeasureText)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).disabled(started != nil)
                TermHelpButton(title: "Starting measure", message: "Optionally enter the musical measure number where this recording begins, such as 12. Later new-measure beats count upward from it and can be used as playback starting points.")
            }
            if !startingMeasureText.isEmpty && validStartingMeasure == nil {
                Text("Enter a whole measure number greater than zero.").font(.footnote).foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                Button("New Measure Beat", systemImage: "1.circle.fill") { addBeat(measure: true) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!startingMeasureText.isEmpty && validStartingMeasure == nil)
                Button("New Beat", systemImage: "circle.fill") { addBeat(measure: false) }
                    .buttonStyle(.bordered).controlSize(.large).disabled(started == nil)
            }
            Text("\(beats.count) beats").font(.title.monospacedDigit())
            Spacer()
            Button("Stop And Save", systemImage: "stop.fill") { showingSave = true }.disabled(beats.isEmpty)
                .buttonStyle(.borderedProminent)
        }
        .onDisappear { preview.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
        .padding(24).background(BatonTheme.canvas).navigationTitle("Touchpad Recording")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { beats.isEmpty ? dismiss() : (confirmingExit = true) } } }
        .confirmationDialog("Discard this touchpad recording?", isPresented: $confirmingExit) {
            Button("Discard", role: .destructive) { dismiss() }; Button("Keep Recording", role: .cancel) {}
        }
        .sheet(isPresented: $showingSave) {
            NavigationStack { Form { TextField("Recording Name", text: $name); Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.batonPage("Save Recording") }
        }
    }

    private func addBeat(measure: Bool) {
        let now = ContinuousClock.now
        if started == nil {
            guard measure else { return }
            currentMeasure = validStartingMeasure
            started = now
        } else if measure, let currentMeasure { self.currentMeasure = currentMeasure + 1 }
        guard let started else { return }
        let elapsed = started.duration(to: now)
        let micros = Int64(elapsed.components.seconds) * 1_000_000 + Int64(elapsed.components.attoseconds / 1_000_000_000_000)
        beats.append(RecordedBeat(elapsedMicroseconds: max(0, micros), isNewMeasure: measure,
                                  measureNumber: currentMeasure, isAccented: measure))
    }

    private var validStartingMeasure: Int? {
        guard let value = Int(startingMeasureText), value > 0 else { return nil }
        return value
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
    @State private var preview = SoundPreview()
    @State private var exactTime = ""
    @State private var editingName = false
    @State private var confirmingBeatDelete = false
    @State private var showingGuide = false
    @State private var playback = RecordingPlaybackController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(store: ConductingRecordingStore, recording: ConductingRecording) {
        self.store = store; self.recording = recording; _working = State(initialValue: recording)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if editingName {
                    TextField("Recording Name", text: Binding(get: { working.name }, set: { value in mutate { $0.name = value } }))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { editingName = false }
                }
                else {
                    HStack {
                        Text(working.name).font(BatonTheme.serif(28, relativeTo: .title2)).lineLimit(1)
                            .onTapGesture(count: 2) { editingName = true }
                        Button { editingName = true } label: {
                            Image(systemName: "pencil")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rename Recording")
                        Spacer()
                    }
                }
                Picker("Sound", selection: Binding(get: { working.currentSound }, set: { value in mutate { $0.currentSound = value }; preview.play(value) })) {
                    ForEach(ClickVoice.allCases) { Text($0.title.capitalized).tag($0) }
                }
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo() }.disabled(undoStack.isEmpty)
                    Button("Redo", systemImage: "arrow.uturn.forward") { redo() }.disabled(redoStack.isEmpty)
                    Spacer()
                    TermHelpButton(title: "Undo and redo", message: "Undo reverses edits made during this visit. Redo reapplies them. The history is cleared after leaving the editor.")
                    if addingBeat {
                        Button("Adding Beats", systemImage: "plus.circle.fill") { addingBeat = false }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Add Beat", systemImage: "plus.circle") { addingBeat = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal)
            HStack {
                Button(playback.playingID == working.id ? "Pause" : "Play",
                       systemImage: playback.playingID == working.id ? "pause.fill" : "play.fill") {
                    preview.stop()
                    if playback.playingID == working.id { playback.pause() }
                    else { playback.resume(working) }
                }
                .buttonStyle(.borderedProminent)
                Button("Restart", systemImage: "backward.end.fill") {
                    preview.stop()
                    playback.stop()
                    playback.toggle(working)
                }
                .buttonStyle(.bordered)
            }
            .disabled(working.beats.isEmpty)
            Divider()
            ScrollView(.vertical) {
                RecordingTimeline(beats: working.beats, selectedBeat: selectedBeat, addingBeat: addingBeat, playback: playback, seek: { playback.seek(working, to: $0) }, resumePlayback: { preview.stop(); playback.resume(working) }) { id in
                    selectedBeat = id
                } addAt: { seconds in
                    mutate { $0.beats.append(RecordedBeat(elapsedMicroseconds: Int64(seconds * 1_000_000), isOriginal: false, isModified: true)) }
                }
                moveBeat: { id, seconds in
                    editBeat(id) { $0.elapsedMicroseconds = Int64((seconds * 1_000_000).rounded()) }
                } beginMove: {
                    playback.pause()
                }
                .frame(height: max(650, (working.duration + 4) * 90))
                .accessibilityLabel("Recording timeline")
                .accessibilityHint(addingBeat ? "Tap to add a beat at that time" : "Tap close to a beat to select it")
            }
            .scrollIndicators(.visible)
            .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            if let selectedBeat, let beat = working.beats.first(where: { $0.id == selectedBeat }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Done Editing") { self.selectedBeat = nil }
                    }
                    Text("Selected beat · \(String(format: "%.3f", beat.elapsedSeconds)) s").font(.headline)
                    LabeledContent("Measure", value: beat.measureNumber.map { String($0) } ?? "Not Numbered")
                    if beat.isNewMeasure {
                        Text("The 1 marks the first beat of this measure.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Toggle("Accent", isOn: Binding(get: { beat.isAccented }, set: { value in editBeat(selectedBeat) { $0.isAccented = value } }))
                        TermHelpButton(title: "Accent", message: "An accented beat plays a higher-frequency version of the selected sound so it stands out.")
                        Toggle("New Measure", isOn: Binding(get: { beat.isNewMeasure }, set: { value in editBeat(selectedBeat) { $0.isNewMeasure = value; if value { $0.isAccented = true } } }))
                        TermHelpButton(title: "New Measure", message: "Marks this as the first beat of a measure. Turning it on also enables Accent.")
                    }
                    HStack {
                        TextField("Time In Seconds", text: $exactTime)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Beat time in seconds")
                        Button("Set Time") {
                            if let seconds = validExactTime {
                                editBeat(selectedBeat) { $0.elapsedMicroseconds = Int64((seconds * 1_000_000).rounded()) }
                            }
                        }.disabled(validExactTime == nil)
                    }
                    HStack {
                        Button("Earlier", systemImage: "arrow.up") { shift(selectedBeat, by: -10_000) }
                        Button("Later", systemImage: "arrow.down") { shift(selectedBeat, by: 10_000) }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingBeatDelete = true }
                    }
                }
                .padding(12).background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
            } else {
                Text(addingBeat ? "Tap the timeline to add a beat." : "Tap a beat to edit, or hold and drag to move it.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.horizontal)
            }
            Button("Revert Beats & Sound") { mutate { value in value.beats = value.originalBeats; value.currentSound = value.originalSound } }
                .font(.footnote).padding(.bottom, 4)
        }
        .onChange(of: selectedBeat) { _, id in
            exactTime = working.beats.first(where: { $0.id == id }).map { String(format: "%.3f", $0.elapsedSeconds) } ?? ""
        }
        .onChange(of: working.beats) { _, _ in
            exactTime = working.beats.first(where: { $0.id == selectedBeat }).map { String(format: "%.3f", $0.elapsedSeconds) } ?? ""
        }
        .background { BatonTheme.canvas.onTapGesture { selectedBeat = nil } }.navigationTitle("Edit Recording").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingGuide = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("Recording editor guide")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedBeat != nil {
                    Button(role: .destructive) { confirmingBeatDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete selected beat")
                }
                Button("Save") { store.update(working); dismiss() }.disabled(!working.isNameValid)
            }
        }
        .confirmationDialog("Delete this beat?", isPresented: $confirmingBeatDelete, titleVisibility: .visible) {
            Button("Delete Beat", role: .destructive) { deleteSelectedBeat() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The beat will be removed from the edited copy. You can still undo it before saving or restore the original later.") }
        .sheet(isPresented: $showingGuide) { NavigationStack { RecordingGuideView() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop(); playback.stop() } }
        .onDisappear { preview.stop(); playback.stop() }
    }

    private var validExactTime: Double? {
        guard let seconds = Double(exactTime), seconds.isFinite, seconds >= 0,
              seconds <= 86_400 else { return nil }
        return seconds
    }

    private func mutate(_ change: (inout ConductingRecording) -> Void) {
        let position = playback.currentPosition
        playback.pause()
        undoStack.append(working); redoStack.removeAll(); change(&working)
        playback.seek(working, to: position)
    }
    private func undo() { playback.stop(); guard let value = undoStack.popLast() else { return }; redoStack.append(working); working = value }
    private func redo() { playback.stop(); guard let value = redoStack.popLast() else { return }; undoStack.append(working); working = value }
    private func editBeat(_ id: UUID, change: (inout RecordedBeat) -> Void) {
        mutate { value in guard let index = value.beats.firstIndex(where: { $0.id == id }) else { return }; change(&value.beats[index]); value.beats[index].isModified = true }
    }
    private func shift(_ id: UUID, by amount: Int64) { editBeat(id) { $0.elapsedMicroseconds = max(0, $0.elapsedMicroseconds + amount) } }
    private func deleteSelectedBeat() {
        guard let selectedBeat else { return }
        mutate { $0.beats.removeAll { $0.id == selectedBeat } }
        self.selectedBeat = nil
    }
}

struct RecordingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Recording A Session") {
                Label("Turn on Record this session before Start practice. Sessions with recording off still start with one tap.", systemImage: "record.circle")
                Label("Only beats that actually make sound are captured. Recording does not change live conducting or firmware.", systemImage: "speaker.wave.2")
                Label("When practice stops, name and save the recording or confirm that you want to discard it.", systemImage: "square.and.arrow.down")
            }
            Section("Recordings") {
                Label("Play or pause generated audio, edit a recording, export WAV audio, or delete with confirmation.", systemImage: "waveform")
                Label("Use Select to delete several recordings at once. Search filters recording names.", systemImage: "checkmark.circle")
                Label("Touchpad recording starts with the first New measure beat.", systemImage: "hand.tap")
                Label("Touchpad recordings can begin at an optional measure number. Numbered recordings can play from any stored measure.", systemImage: "number")
            }
            Section("Editor") {
                Label("Blue dots mark regular beats and measure starts. A 1 marks the first beat of a measure, not its measure number. Other accented beats are orange. The selected beat turns red. Tap empty timeline space or Done Editing to clear the selection.", systemImage: "circle.inset.filled")
                Label("The timeline scrolls vertically. Turn on Add beat, then tap its time position to insert one.", systemImage: "plus.circle")
                Label("The timeline includes open time after the final beat so you can add later beats without moving an existing one first.", systemImage: "arrow.down.to.line")
                Label("Accent and New measure switches show and change the selected beat's current state. A new measure automatically enables accent.", systemImage: "switch.2")
                Label("Hold and drag a dot to move it, or enter its exact time in seconds (0–86400) and tap Set time. Earlier and Later move by 10 milliseconds. Delete asks for confirmation and remains undoable until you save.", systemImage: "arrow.up.arrow.down")
                Label("Revert restores the original beats and sound but keeps the recording's current name.", systemImage: "arrow.counterclockwise")
            }
        }
        .batonPage("Recording Guide")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct RecordingTimeline: View {
    let beats: [RecordedBeat]
    let selectedBeat: UUID?
    let addingBeat: Bool
    let playback: RecordingPlaybackController
    let seek: (TimeInterval) -> Void
    let resumePlayback: () -> Void
    let select: (UUID?) -> Void
    let addAt: (TimeInterval) -> Void
    let moveBeat: (UUID, TimeInterval) -> Void
    let beginMove: () -> Void
    @State private var scrubOrigin: TimeInterval?
    @State private var resumeAfterScrub = false
    @GestureState private var dragging: UUID?
    @GestureState private var dragOffset: CGFloat = 0

    private var duration: TimeInterval { max(5, (beats.map(\.elapsedSeconds).max() ?? 0) + 4) }

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
                    let y = CGFloat(beat.elapsedSeconds / duration) * proxy.size.height + (dragging == beat.id ? dragOffset : 0)
                    Image(systemName: beat.isNewMeasure ? "1.circle.fill" : (beat.isAccented ? "circle.inset.filled" : "circle.fill"))
                        .font(.title3)
                        .foregroundStyle(selectedBeat == beat.id || dragging == beat.id ? Color.red : beat.isNewMeasure ? BatonTheme.ultramarine : beat.isAccented ? Color.orange : BatonTheme.ultramarine)
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                    .onTapGesture { select(beat.id) }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("recordingTimeline")))
                            .updating($dragging) { value, state, _ in
                                if case .second(true, _) = value { state = beat.id }
                            }
                            .updating($dragOffset) { value, state, _ in
                                if case .second(true, let drag?) = value { state = drag.translation.height }
                            }
                            .onChanged { value in
                                if case .second(true, _) = value { select(beat.id); beginMove() }
                            }
                            .onEnded { value in
                                if case .second(true, let drag?) = value {
                                    let seconds = max(0, min(duration, beat.elapsedSeconds + Double(drag.translation.height / proxy.size.height) * duration))
                                    moveBeat(beat.id, seconds)
                                }
                            }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(beat.id) }
                    .accessibilityHint("Tap to edit. Hold and drag to move.")
                    .accessibilityAddTraits(selectedBeat == beat.id ? [.isSelected] : [])
                    .buttonStyle(.plain).position(x: 96, y: min(proxy.size.height - 12, max(12, y)))
                    .accessibilityLabel("\(beat.isNewMeasure ? "Measure" : beat.isAccented ? "Accented" : "Regular") beat at \(String(format: "%.3f", beat.elapsedSeconds)) seconds")
                }
                TimelineView(.animation(paused: playback.playingID == nil)) { _ in
                    let time = min(duration, playback.currentPosition)
                    let y = CGFloat(time / duration) * proxy.size.height
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(Color.red, lineWidth: 2)
                        .allowsHitTesting(false)
                        // Keep the draggable area to the right of beat targets.
                        ZStack(alignment: .trailing) {
                            Color.clear
                            Text(String(format: "%.3f s", time))
                                .font(.caption.monospacedDigit()).foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .background(BatonTheme.surface)
                                .offset(y: -13)
                        }
                        .frame(width: max(44, proxy.size.width - 128), height: 44)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("recordingTimeline"))
                            .onChanged { value in
                                if scrubOrigin == nil {
                                    scrubOrigin = playback.currentPosition
                                    resumeAfterScrub = playback.playingID != nil
                                }
                                seek((scrubOrigin ?? 0) + Double(value.translation.height / proxy.size.height) * duration)
                            }
                            .onEnded { _ in
                                scrubOrigin = nil
                                if resumeAfterScrub { resumePlayback() }
                                resumeAfterScrub = false
                            })
                        .accessibilityLabel("Playback Position")
                        .accessibilityValue(String(format: "%.3f seconds", time))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: seek(time + 0.1)
                            case .decrement: seek(time - 0.1)
                            @unknown default: break
                            }
                        }
                        .position(x: (proxy.size.width + 128) / 2, y: y)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                if addingBeat {
                    Text("Tap anywhere to add a beat").font(.caption).foregroundStyle(.secondary)
                        .padding(8).background(.thinMaterial, in: Capsule()).position(x: proxy.size.width / 2, y: 18)
                }
            }
            .coordinateSpace(name: "recordingTimeline")
            .transaction { $0.animation = nil }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                let seconds = max(0, min(duration, Double(event.location.y / proxy.size.height) * duration))
                if addingBeat { addAt(seconds) }
                else {
                    // Match the visible 48 × 44 point dot target, not a time window
                    // that grows with the length of the recording.
                    let nearest = beats.min {
                        abs(CGFloat($0.elapsedSeconds / duration) * proxy.size.height - event.location.y)
                        < abs(CGFloat($1.elapsedSeconds / duration) * proxy.size.height - event.location.y)
                    }
                    if let nearest,
                       abs(event.location.x - 96) <= 24,
                       abs(min(proxy.size.height - 12, max(12, CGFloat(nearest.elapsedSeconds / duration) * proxy.size.height)) - event.location.y) <= 22 {
                        select(nearest.id)
                    } else {
                        select(nil)
                    }
                }
            })
        }
        .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct TermHelpButton: View {
    let title: String
    let message: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "questionmark.circle") }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("What does \(title) mean?")
            .alert(title, isPresented: $showing) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
}
