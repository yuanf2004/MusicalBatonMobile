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
                    Label("Sound & movement", systemImage: "music.note")
                }
                Text("Stop practice before changing your sound or sensitivity.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Connected batons") {
                if session.manager.isConnected {
                    NavigationLink { BatonDetailsView(session: session) } label: {
                        Label(session.deviceName, systemImage: "checkmark.circle")
                    }
                } else {
                    Text("No baton connected").foregroundStyle(.secondary)
                    Text("Connect from Home to view details or give your baton a nickname.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("One baton can be connected at a time.").font(.footnote).foregroundStyle(.secondary)
            }
            // Keep Bluetooth options at the bottom, as requested.
            Section {
                Picker("Search duration", selection: $preferences.scanSeconds) {
                    ForEach(ConnectionTimePolicy.scanChoices, id: \.self) {
                        Text(ConnectionTimePolicy.title(seconds: $0)).tag($0)
                    }
                }
                Picker("Connection time limit", selection: $preferences.connectionSeconds) {
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
    @State private var nickname = ""
    @State private var renameError: String?

    var body: some View {
        Form {
            if session.manager.isConnected, let device = session.manager.activeDevice {
                Section("Name on this iPhone") {
                    TextField("Baton nickname", text: $nickname)
                        .onSubmit { saveName(device.id) }
                    Button("Save name") { saveName(device.id) }
                        .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count > 40)
                    Text("Up to 40 characters. A blank name restores the advertised name. This nickname is saved only in this app; it doesn't rename the baton for other phones.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let renameError { Text(renameError).foregroundStyle(.red) }
                }
                Section("Identity") {
                    LabeledContent("Advertised name", value: device.name)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iPhone Bluetooth identifier").font(.headline)
                        Text(device.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text("This identifier is assigned by iOS. It is not the baton's serial number or Bluetooth MAC address.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let serial = reportedValue("2A25") { LabeledContent("Serial number", value: serial) }
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
                    Button("Disconnect baton", role: .destructive) { session.manager.disconnect() }
                        .disabled(session.manager.isDisconnecting)
                }
            } else {
                Section { Text("This baton is disconnected. Connect from Home to edit its name or view details.") }
            }
        }
        .batonPage("Your baton")
        .onAppear {
            guard let d = session.manager.activeDevice else { return }
            nickname = session.preferences.nicknames[d.id.uuidString] ?? ""
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
        if session.preferences.rename(id: id, name: nickname) { renameError = "Name saved." }
        else { renameError = "Choose a name with no more than 40 characters." }
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
            Section("Start here") {
                DisclosureGroup("How do I set up my baton?") {
                    guide(["Power on your baton.", "Press its button three times. A breathing Bluetooth light means it's advertising.", "On Home, tap Find my baton, allow Bluetooth access and select your baton.", "Choose your sound and movement sensitivity. You can preview sounds before connecting.", "Tap Start practice. Hold the baton still briefly, then conduct. Keep the app open while you practice."])
                }
                DisclosureGroup("How do I connect again?") {
                    Text("Triple-press the baton button and search from Home. Advertising times out after 60 seconds without a connection. Triple-press again if the light goes out. Stop searching or disconnect on other phones before trying this phone.")
                }
            }
            Section("Questions & answers") {
                qa("Why can't I see my baton?", "Check power and stay nearby. Triple-press its button to start advertising, then search again. The search stops after your chosen duration in Settings. If the baton is already connected to another phone or the debug app, disconnect it there first.")
                qa("What if Bluetooth access is off?", "Turn Bluetooth on in iPhone Settings. If you denied access, allow Musical Baton to use Bluetooth under Settings → Privacy & Security → Bluetooth, then return and search again.")
                qa("Why isn't it making sound?", "Check media volume and the current speaker/headphone output. Stop practice and use Test sound to check playback. Then connect, wait for setup to finish and start practice again. Firm strokes may help; choose Gentle sensitivity for smaller movements.")
                qa("Why are some movements silent?", "Practice filters out weak strokes and idle motion. Hold still for a moment before starting. Only accepted beats make a sound; pauses and missed beats are not replayed.")
                qa("Why did practice stop?", "Leaving the app, disconnecting, a phone call, or changing headphones can stop playback. A connection time limit can also disconnect your baton. Return to Home, reconnect if needed and tap Start practice.")
                qa("What do the health indicators mean?", "Connected means the Bluetooth link is active. Receiving motion means a valid motion packet arrived within the past three seconds. Waiting for data is not a battery or sensor failure diagnosis. The current firmware doesn't report battery charge.")
                qa("Does renaming change the baton itself?", "No. Nicknames are saved on this iPhone, matched by the Bluetooth identifier assigned by iOS. Other phones continue to see the advertised name.")
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
