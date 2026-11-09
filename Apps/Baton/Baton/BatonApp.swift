import SwiftUI
import CoreBluetooth

@main
struct BatonApp: App {
    var body: some Scene {
        WindowGroup { BatonOpeningView() }
    }
}

struct PracticeView: View {
    @State private var manager = BLEManager()
    @State private var showingConnection = false
    @State private var showingPreferences = false
    @Environment(\.scenePhase) private var scenePhase

    private var canConduct: Bool {
        manager.isConnected && !manager.isDisconnecting && !manager.isDiscoveringServices &&
        manager.batonBeatCharacteristic != nil && manager.batonSettingsCharacteristic != nil &&
        manager.conductingProfiles.selected != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Make music\nwith your movement.")
                            .font(BatonTheme.serif(48, relativeTo: .largeTitle))
                            .foregroundStyle(BatonTheme.ultramarine)
                        Text("Connect your baton, find your sound, and start conducting.")
                            .foregroundStyle(.secondary)
                    }
                    connectionCard
                    practiceCard
                    Button { showingPreferences = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "slider.horizontal.3").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your sound").font(BatonTheme.serif(28, relativeTo: .title2))
                                Text(manager.conductingProfiles.selected.map {
                                    "\($0.otherBeatSound.title) · \($0.sensitivity.title)"
                                } ?? "Choose a sound and sensitivity")
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(20)
                        .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.conducting.isEnabled)
                    Text("Keep the app open while you practice. Sound plays through your current audio output; starting practice pauses other media.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(BatonTheme.canvas)
            .navigationTitle("Musical Baton")
            .toolbar { ToolbarItem(placement: .principal) {
                Text("Musical Baton").font(BatonTheme.serif(26, relativeTo: .title2))
                    .foregroundStyle(BatonTheme.ultramarine)
            } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(BatonTheme.ultramarine)
        .sheet(isPresented: $showingConnection) {
            ConnectionView(manager: manager)
        }
        .sheet(isPresented: $showingPreferences) {
            SoundPreferencesView(store: manager.conductingProfiles)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                manager.stopConducting(reason: "Practice paused. Tap Start practice when you return.")
                manager.stopScanning()
            }
        }
        .alert("Connection needs attention", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { manager.errorMessage = nil }
        } message: { Text(manager.errorMessage ?? "") }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(manager.isConnected ? "Baton connected" : "Connect your baton",
                  systemImage: manager.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                .font(BatonTheme.serif(28, relativeTo: .title2))
                .foregroundStyle(manager.isConnected ? Color.green : BatonTheme.ultramarine)
            if manager.isConnected {
                Text(manager.activeDevice?.name ?? "Musical Baton").foregroundStyle(.secondary)
                if manager.isDiscoveringServices {
                    ProgressView("Getting your baton ready…")
                } else if !canConduct {
                    Text("This baton isn't ready for practice. Check that it has the current Musical Baton firmware and a saved sound profile.")
                        .foregroundStyle(.secondary)
                }
                Button(manager.isDisconnecting ? "Disconnecting…" : "Disconnect", role: .destructive) {
                    manager.disconnect()
                }.disabled(manager.isDisconnecting)
            } else {
                Text("Press your baton's button three times. Its blinking light means it is ready to connect.")
                    .foregroundStyle(.secondary)
                Button("Find my baton", systemImage: "magnifyingglass") { showingConnection = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(BatonTheme.ultramarine.opacity(0.10)) }
    }

    private var practiceCard: some View {
        VStack(spacing: 20) {
            Image(systemName: manager.conducting.isReady ? "waveform" : "music.note")
                .font(.system(size: 48)).foregroundStyle(BatonTheme.ultramarine)
                .accessibilityHidden(true)
            Text(manager.conducting.isReady ? "Follow your rhythm" : "Ready when you are")
                .font(BatonTheme.serif(34, relativeTo: .title))
                .foregroundStyle(BatonTheme.ultramarine)
            Text(manager.conducting.isEnabled
                 ? (manager.conducting.isReady ? "Hold still for a moment, then conduct. Each accepted stroke plays your sound." : "Preparing your baton and sound…")
                 : "Choose a comfortable grip and give yourself room to move.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let error = manager.conducting.error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if manager.conducting.isEnabled {
                Text("\(manager.conducting.beatCount)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("beats played").foregroundStyle(.secondary)
                Button("Try your sound", systemImage: "speaker.wave.2") {
                    manager.conducting.testSound()
                }.disabled(!manager.conducting.isReady)
            }
            Button {
                manager.setConductingMode(!manager.conducting.isEnabled)
            } label: {
                Text(manager.conducting.isEnabled ? "Stop practice" : "Start practice")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!manager.conducting.isEnabled && !canConduct)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(BatonTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(BatonTheme.ultramarine.opacity(0.10)) }
    }
}

private struct ConnectionView: View {
    let manager: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Triple-press the baton button, then choose your baton below. If its light stops blinking, triple-press again.")
                    Label(manager.bluetoothStatus, systemImage: "antenna.radiowaves.left.and.right")
                }
                Section("Nearby batons") {
                    if let device = manager.activeDevice {
                        ProgressView("Connecting to \(device.name)…")
                        Button("Cancel connection", role: .cancel) { manager.disconnect() }
                            .disabled(manager.isDisconnecting)
                    } else {
                        ForEach(manager.devices.filter(\.isConnectable)) { device in
                            Button { manager.connect(to: device) } label: {
                                Label(device.name, systemImage: "music.note")
                            }
                        }
                        if manager.devices.isEmpty {
                            Text(manager.isScanning ? "Looking for your baton…" : "No baton found yet.")
                                .foregroundStyle(.secondary)
                        }
                        Button(manager.isScanning ? "Stop searching" : "Search again") {
                            if manager.isScanning { manager.stopScanning() }
                            else { search() }
                        }.disabled(manager.bluetoothState != .poweredOn)
                    }
                    if let error = manager.errorMessage { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BatonTheme.canvas)
            .navigationTitle("Find your baton")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Find your baton").font(BatonTheme.serif(26, relativeTo: .title2))
                        .foregroundStyle(BatonTheme.ultramarine)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(BatonTheme.ultramarine)
        .onAppear { search() }
        .onChange(of: manager.bluetoothState) { _, state in
            if state == .poweredOn { search() }
        }
        .onChange(of: manager.isConnected) { _, connected in
            if connected { dismiss() }
        }
        .onDisappear {
            manager.stopScanning()
            if !manager.isConnected { manager.disconnect() }
        }
    }

    private func search() {
        manager.startScanning(serviceUUIDs: [BatonMotionPacket.serviceUUID])
    }
}

private struct SoundPreferencesView: View {
    let store: ConductingProfileStore
    @State private var draft = ConductingProfile(name: "My sound")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your sound") {
                    TextField("Name", text: $draft.name)
                    Picker("Sound", selection: $draft.otherBeatSound) {
                        ForEach(ClickVoice.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Movement", selection: $draft.sensitivity) {
                        ForEach(DetectionSensitivity.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Choose Gentle for smaller movements or Deliberate for firmer strokes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(BatonTheme.canvas)
            .navigationTitle("Your sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your sound").font(BatonTheme.serif(26, relativeTo: .title2))
                        .foregroundStyle(BatonTheme.ultramarine)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.save(draft) { dismiss() } }.disabled(!draft.isValid)
                }
            }
        }
        .tint(BatonTheme.ultramarine)
        .onAppear { if let selected = store.selected { draft = selected } }
    }
}
