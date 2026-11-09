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
                Label("One accepted beat. One sound.", systemImage: "music.note")
                    .font(.title2.bold())
                Text("Hold the baton still for a second to calibrate, then conduct. Playback follows detected motion peaks and continues automatically after pauses or missed beats.")
                    .foregroundStyle(.secondary)
            }
            Section("Profile") {
                if let profile = manager.conductingProfiles.selected {
                    Text(profile.name).font(.headline)
                    Text("\(profile.sensitivity.title) · \(profile.otherBeatSound.title)")
                } else { Text("Create and select a profile to begin.") }
                Button("Choose or Edit Profiles", systemImage: "person.crop.rectangle") {
                    manager.stopConducting(reason: "Select a profile, then enable Conducting Mode.")
                    showingProfiles = true
                }
            }
            Section("Beat filtering") {
                Picker("Mode", selection: Binding(get: { manager.conducting.filterMode },
                    set: { manager.conducting.filterMode = $0 })) {
                    ForEach(BeatFilterMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(manager.conducting.isEnabled)
                Stepper("Strength above \(manager.conducting.strengthThreshold)", value: Binding(
                    get: { manager.conducting.strengthThreshold },
                    set: { manager.conducting.strengthThreshold = $0 }), in: 0...99)
                    .disabled(manager.conducting.isEnabled)
                Text("Both modes reject weak beats. ML also suppresses idle motion and waits for fresh motion samples. It uses Zach’s gesture model, adapted for the slower Bluetooth stream; accuracy on the phone is not yet validated.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Turn Conducting Mode off to change filtering. Peak + strength matches the PC’s default mode; Peak + ML adds its gesture filter.")
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
                    Text("Select a saved profile and connect to the baton. Wait for discovery to finish.")
                        .foregroundStyle(.orange)
                }
                if let error = manager.conducting.error { Text(error).foregroundStyle(.red) }
                Button("Test Sound", systemImage: "speaker.wave.2") { manager.conducting.testSound() }
                    .disabled(!manager.conducting.isReady)
            }
            Section("This session") {
                LabeledContent("Beats played", value: String(manager.conducting.beatCount))
                LabeledContent("Beats filtered", value: String(manager.conducting.filteredCount))
                if manager.conducting.filterMode == .gesture {
                    LabeledContent("Latest gesture", value: manager.conducting.gestureLabel)
                }
                if let reason = manager.conducting.lastFilterReason {
                    LabeledContent("Last filter reason", value: reason)
                }
                if let beat = manager.conducting.lastBeat {
                    LabeledContent("Tempo", value: beat.bpmTenths == 0 ? "Not stable yet" :
                        String(format: "%.1f BPM", Double(beat.bpmTenths) / 10))
                    LabeledContent("Last played strength", value: "\(beat.strength) / 100")
                }
                Text("There is no measure or downbeat counter. Gaps never require a reset, and missing beats are not replayed. ML resumes automatically once fresh motion is available.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Audio timing") {
                LabeledContent("Output", value: manager.conducting.audioRoute)
                LabeledContent("Actual buffer", value: String(format: "%.1f ms", manager.conducting.audioBufferMS))
                LabeledContent("Reported output latency", value: String(format: "%.1f ms", manager.conducting.audioOutputMS))
                if let ms = manager.conducting.callbackToScheduleMS {
                    LabeledContent("Callback to audio schedule", value: String(format: "%.2f ms", ms))
                }
                Text("These are audio-session readings and app processing time, not total movement-to-sound latency. Test with the phone speaker first; wireless audio adds another link.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sound") {
                Text("Enabling this mode interrupts other media to prioritize responsive sound. Use the phone’s media volume. Sound uses your current audio output, including headphones if connected. Use the phone speaker for initial timing tests.")
                Text("Keep this screen open. Leaving it, backgrounding the app, disconnecting, or an audio interruption turns the mode off.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Conducting Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showingProfiles) {
            NavigationStack { ConductingProfilesView(store: manager.conductingProfiles) }
        }
        .onDisappear { manager.stopConducting(reason: "Conducting Mode closed.") }
    }
}
