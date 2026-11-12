import SwiftUI
import CoreBluetooth

extension View {
    func batonPage(_ title: String) -> some View {
        self.scrollContentBackground(.hidden)
            .background(BatonTheme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(BatonTheme.serif(26, relativeTo: .title2))
                        .foregroundStyle(BatonTheme.ultramarine)
                }
            }
    }
}

struct SettingsView: View {
    let session: ProductSession

    var body: some View {
        @Bindable var preferences = session.preferences
        Form {
            Section {
                Text("Make the baton feel like yours.")
                    .font(BatonTheme.serif(30, relativeTo: .title))
                    .foregroundStyle(BatonTheme.ultramarine)
                Text("Your preferences are saved on this iPhone.").foregroundStyle(.secondary)
            }
            Section("Practice") {
                NavigationLink { SoundPreferencesView(store: session.manager.conductingProfiles,
                                                     isPracticing: session.manager.conducting.isEnabled) } label: {
                    Label("Sound & Movement", systemImage: "music.note")
                }
                Text("Stop practice before changing your sound or sensitivity.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle(isOn: $preferences.recordSessionsByDefault) {
                    HStack {
                        Text("Record Sessions By Default")
                        TermHelpButton(title: "Recording default", message: "Sets the initial state of Record this session on Home. You can still change it before each practice session.")
                    }
                }
                Text("You can override this on Home before each session. Recording stores only the timing of beats you hear, not microphone audio.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Connected Batons") {
                if session.manager.isConnected {
                    NavigationLink { BatonDetailsView(session: session) } label: {
                        Label(session.deviceName, systemImage: "checkmark.circle")
                    }
                } else {
                    Text("No baton connected").foregroundStyle(.secondary)
                    Text("Connect from Home to view details or rename your baton.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("One baton can be connected at a time.").font(.footnote).foregroundStyle(.secondary)
            }
            // Keep Bluetooth options at the bottom, as requested.
            Section {
                Picker("Search Duration", selection: $preferences.scanSeconds) {
                    ForEach(ConnectionTimePolicy.scanChoices, id: \.self) {
                        Text(ConnectionTimePolicy.title(seconds: $0)).tag($0)
                    }
                }
                Picker("Connection Time Limit", selection: $preferences.connectionSeconds) {
                    ForEach(ConnectionTimePolicy.connectionChoices, id: \.self) {
                        Text(ConnectionTimePolicy.title(seconds: $0)).tag($0)
                    }
                }
                Text("Search duration controls how long this phone looks for a baton. It doesn't change the baton's advertising window.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("The connection limit starts when a baton connects. Changes apply to the current connection. iOS can suspend this app in the background; an expired connection is ended when the app runs again.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Bluetooth") }
        }
        .batonPage("Settings")
    }
}

struct BatonDetailsView: View {
    let session: ProductSession
    @State private var deviceName = ""
    @State private var renameError: String?

    var body: some View {
        Form {
            if session.manager.isConnected, let device = session.manager.activeDevice {
                Section("Baton Bluetooth Name") {
                    TextField("Baton Name", text: $deviceName)
                        .onSubmit { saveName(device.id) }
                        .disabled(session.manager.isRenamingBaton || session.manager.conducting.isEnabled)
                    Button(session.manager.isRenamingBaton ? "Saving On Baton…" : "Save On Baton") { saveName(device.id) }
                        .disabled(session.manager.batonNameCharacteristic == nil || session.manager.isRenamingBaton ||
                                  session.manager.conducting.isEnabled || (try? BatonIdentity.validatedName(deviceName)) == nil)
                    if session.manager.batonNameCharacteristic == nil {
                        Text("Install the name-enabled baton firmware to change this device's Bluetooth name.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Saved on the baton and kept after reboot. Other phones see this name the next time it advertises. Use 1–20 UTF-8 bytes; emoji and accented letters may use several bytes.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if session.manager.conducting.isEnabled {
                        Text("Stop practice before renaming your baton.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = session.manager.batonNameError { Text(error).foregroundStyle(.red) }
                    if let message = session.manager.batonNameMessage { Text(message).foregroundStyle(.secondary) }
                    if let renameError { Text(renameError).foregroundStyle(.red) }
                }
                Section("Identity") {
                    LabeledContent("Bluetooth Name", value: session.deviceName)
                    Text("All batons share the same service identifier, so changing this name does not affect discovery.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iPhone Bluetooth identifier").font(.headline)
                        Text(device.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text("This identifier is assigned by iOS. It is not the baton's serial number or Bluetooth MAC address.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let serial = reportedValue("2A25") { LabeledContent("Serial Number", value: serial) }
                    if let firmware = reportedValue("2A26") { LabeledContent("Firmware", value: firmware) }
                    if let hardware = reportedValue("2A27") { LabeledContent("Hardware", value: hardware) }
                    if reportedValue("2A25") == nil && reportedValue("2A26") == nil && reportedValue("2A27") == nil {
                        Text("This baton doesn't report a serial number or firmware/hardware revision.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Connection") {
                    LabeledContent("Status", value: session.manager.isDisconnecting ? "Disconnecting" : "Connected")
                    LabeledContent("Motion", value: session.motionIsFresh ? "Receiving" : "Waiting for data")
                    Button("Disconnect Baton", role: .destructive) { session.manager.disconnect() }
                        .disabled(session.manager.isDisconnecting)
                }
            } else {
                Section { Text("This baton is disconnected. Connect from Home to edit its name or view details.") }
            }
        }
        .batonPage("Your Baton")
        .onChange(of: session.manager.batonDeviceName) { _, name in
            if let name, !session.manager.isRenamingBaton { deviceName = name }
        }
        .onAppear {
            guard let d = session.manager.activeDevice else { return }
            deviceName = session.manager.batonDeviceName ?? d.name
            for model in session.manager.services.filter({ $0.service.uuid == CBUUID(string: "180A") }).flatMap(\.characteristics) {
                if ["2A25", "2A26", "2A27"].contains(model.characteristic.uuid.uuidString),
                   model.characteristic.properties.contains(.read), !model.readPending {
                    session.manager.read(model)
                }
            }
        }
    }
    private func saveName(_ id: UUID) {
        guard session.manager.isConnected, session.manager.activeDevice?.id == id else { return }
        renameError = nil
        session.manager.renameBaton(deviceName)
    }
    private func reportedValue(_ uuid: String) -> String? {
        guard let value = session.manager.services.first(where: { $0.service.uuid == CBUUID(string: "180A") })?
            .characteristics.first(where: { $0.characteristic.uuid == CBUUID(string: uuid) })?.value,
              let text = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !text.isEmpty else { return nil }
        return text
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section {
                Text("A little help,\nback to making music.")
                    .font(BatonTheme.serif(36, relativeTo: .largeTitle))
                    .foregroundStyle(BatonTheme.ultramarine)
            }
            Section("Start Here") {
                DisclosureGroup("How do I set up my baton?") {
                    guide(["Power on your baton.", "Press its button three times. A breathing Bluetooth light means it's advertising.", "On Home, tap Find my baton, allow Bluetooth access and select your baton.", "Choose your sound and movement sensitivity. You can preview sounds before connecting.", "Tap Start practice. Hold the baton still briefly, then conduct. Keep the app open while you practice."])
                }
                DisclosureGroup("How do I connect again?") {
                    Text("Triple-press the baton button and search from Home. Advertising times out after 60 seconds without a connection. Triple-press again if the light goes out. Stop searching or disconnect on other phones before trying this phone.")
                }
            }
            Section("Questions & Answers") {
                qa("Why can't I see my baton?", "Check power and stay nearby. Triple-press its button to start advertising, then search again. The search stops after your chosen duration in Settings. If the baton is already connected to another phone or the debug app, disconnect it there first.")
                qa("What if Bluetooth access is off?", "Turn Bluetooth on in iPhone Settings. If you denied access, allow Musical Baton to use Bluetooth under Settings → Privacy & Security → Bluetooth, then return and search again.")
                qa("Why isn't it making sound?", "Check media volume and the current speaker/headphone output. Stop practice and use Test sound to check playback. Then connect, wait for setup to finish and start practice again. Firm strokes may help; choose Gentle sensitivity for smaller movements.")
                qa("Why are some movements silent?", "Practice filters out weak strokes and idle motion. Hold still for a moment before starting. Only accepted beats make a sound; pauses and missed beats are not replayed.")
                qa("What does session recording save?", "It stores the timing of beats that actually played and the selected sound. It never records microphone audio or changes how the baton performs. Open Recordings to correct timing, add beats, play the result, or export a generated WAV audio file.")
                qa("Why did practice stop?", "Leaving the app, disconnecting, a phone call, or changing headphones can stop playback. A connection time limit can also disconnect your baton. Return to Home, reconnect if needed and tap Start practice.")
                qa("What do the health indicators mean?", "Connected means the Bluetooth link is active. Receiving motion means a valid motion packet arrived within the past three seconds. Waiting for data is not a battery or sensor failure diagnosis. The current firmware doesn't report battery charge.")
                qa("Does renaming change the baton itself?", "Yes, with the name-enabled firmware. Settings → Connected batons → Your baton lets you save its Bluetooth name on the device. The app confirms that it was saved. It survives reboot and other phones see it on the next advertising session. Some phones may temporarily show a cached name. Stop practice before renaming.")
                qa("Will changing the name hide my baton?", "No. The app looks for the shared Musical Baton service identifier, not the words Smart Baton. Each baton keeps its own individual Bluetooth identifier, even when several have the same name.")
                qa("Can I add subdivisions or measure accents?", "You can choose a single accented click sound, but automatic subdivisions and first-beat-of-measure accents are not supported yet. Every accepted beat uses the selected sound.")
                qa("Can the app update firmware or change sensor sampling?", "Those features aren't available with the current baton firmware. This app doesn't expose controls for them. Use the project's existing wired programming workflow for firmware updates.")
            }
        }
        .batonPage("Help")
    }
    private func qa(_ question: String, _ answer: String) -> some View {
        DisclosureGroup(question) { Text(answer).foregroundStyle(.secondary).padding(.vertical, 8) }
    }
    private func guide(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
            }
        }.foregroundStyle(.secondary).padding(.vertical, 8)
    }
}
