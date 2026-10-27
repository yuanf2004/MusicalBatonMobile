import SwiftUI

struct ConductingModeView: View {
    let manager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingProfiles = false

    private var available: Bool {
        manager.isConnected && !manager.isDisconnecting && manager.batonBeatCharacteristic != nil && manager.batonSettingsCharacteristic != nil && manager.conductingProfiles.selected != nil
    }

    var body: some View {
        Form {
            Section {
                Label("One stop. One sound.", systemImage: "music.note")
                    .font(.title2.bold())
                Text("Hold the baton still for a second to calibrate, then make a conducting stroke and stop. Each beat detected by the baton plays a short click.")
                    .foregroundStyle(.secondary)
            }
            Section("Profile") {
                if let profile = manager.conductingProfiles.selected {
                    Text(profile.name).font(.headline)
                    Text("\(profile.beatsPerMeasure) beats per measure · \(profile.sensitivity.title)")
                    Text("Beat 1: \(profile.downbeatSound.title) · Others: \(profile.otherBeatSound.title)")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("Create and select a profile to begin.") }
                Button("Choose or Edit Profiles", systemImage: "person.crop.rectangle") {
                    manager.stopConducting(reason: "Select a profile, then enable Conducting Mode.")
                    showingProfiles = true
                }
                Text("When enabled, your next detected stroke starts beat 1. Tempo follows your gestures.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Conducting") {
                Toggle("Conducting Mode", isOn: Binding(
                    get: { manager.conducting.isEnabled },
                    set: { manager.setConductingMode($0) }
                ))
                .disabled(!available)
                Label(manager.conducting.status,
                      systemImage: manager.conducting.isReady ? "waveform" : "info.circle")
                if !available {
                    Text("Select a saved profile and connect to a baton running the profile-enabled firmware. Wait for discovery to finish.")
                        .foregroundStyle(.orange)
                }
                if let error = manager.conducting.error {
                    Text(error).foregroundStyle(.red)
                }
                Button("Test Beat 1 Sound", systemImage: "speaker.wave.2") {
                    manager.conducting.testSound(downbeat: true)
                }
                .disabled(!manager.conducting.isReady)
                Button("Test Other Beat Sound", systemImage: "speaker.wave.1") {
                    manager.conducting.testSound(downbeat: false)
                }
                .disabled(!manager.conducting.isReady)
                Button("Next beat is 1", systemImage: "arrow.counterclockwise") {
                    manager.conducting.resetDownbeat()
                }
                .disabled(!manager.conducting.isReady)
            }
            Section("This session") {
                LabeledContent("Beat in measure", value: manager.conducting.needsDownbeat ? "Reset needed" :
                    manager.conducting.beatInMeasure == 0 ? "Waiting for 1" : String(manager.conducting.beatInMeasure))
                LabeledContent("Beats played", value: String(manager.conducting.beatCount))
                if let beat = manager.conducting.lastBeat {
                    LabeledContent("Tempo", value: beat.bpmTenths == 0 ? "Not stable yet" :
                        String(format: "%.1f BPM", Double(beat.bpmTenths) / 10))
                    LabeledContent("Motion strength", value: "\(beat.strength) / 100")
                }
                Text("A stable tempo is not required. Missed or extra detections can shift the count; use Next beat is 1 to realign. After a pause over two seconds or a missing Bluetooth event, reset the count to resume.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sound") {
                Text("Use the phone’s media volume. Sound uses your current audio output, including headphones if connected. Use the phone speaker for initial timing tests.")
                Text("Keep this screen open. Leaving it, backgrounding the app, disconnecting, or an audio interruption turns the mode off.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Conducting Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $showingProfiles) {
            NavigationStack { ConductingProfilesView(store: manager.conductingProfiles) }
        }
        .onDisappear { manager.stopConducting(reason: "Conducting Mode closed.") }
    }
}
