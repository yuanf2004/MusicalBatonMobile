import SwiftUI

struct IMURecordingView: View {
    let manager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var durationSeconds = 30
    @State private var progress = IMURecorder.Progress()
    @FocusState private var durationFocused: Bool

    private var recorder: IMURecorder { manager.imuRecorder }

    var body: some View {
        Form {
            Section {
                if let model = manager.batonMotionCharacteristic {
                    Toggle("Motion Notifications", isOn: Binding(
                        get: { model.isNotifying },
                        set: { manager.setNotifications($0, for: model) }
                    ))
                    .disabled(model.notificationPending || manager.isDisconnecting)
                    if model.notificationPending { ProgressView("Updating notifications…") }
                } else {
                    Text("Connect to the baton motion service to start a recording.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    TextField("Seconds", value: $durationSeconds, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .frame(width: 80).focused($durationFocused)
                    Text("seconds").foregroundStyle(.secondary)
                }
                .disabled(recorder.isRecording || recorder.isFinishing)
                HStack {
                    ForEach([10, 30, 60, 120], id: \.self) { seconds in
                        Button("\(seconds) s") { durationSeconds = seconds; durationFocused = false }
                            .buttonStyle(.bordered)
                    }
                }
                .disabled(recorder.isRecording || recorder.isFinishing)
                if recorder.isRecording {
                    Button("Stop Recording", role: .destructive) { recorder.stop() }
                } else {
                    Button("Start Recording") {
                        durationFocused = false
                        manager.startIMURecording(duration: Double(durationSeconds))
                    }
                    .disabled(recorder.isFinishing || !manager.isConnected || manager.isDisconnecting
                              || manager.batonMotionCharacteristic?.isNotifying != true
                              || manager.batonMotionCharacteristic?.notificationPending == true
                              || !(1...600).contains(durationSeconds))
                }
            } header: { Text("Record IMU") } footer: {
                Text("Choose 1–600 seconds. Keep the app open. Recording continues if you close this screen, and ends when the timer finishes, notifications stop, or the device disconnects. Live motion parsing can be off.")
            }

            Section("Recording Status") {
                if recorder.isRecording {
                    Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
                    ProgressView(value: min(progress.elapsed, recorder.targetDuration), total: recorder.targetDuration)
                    LabeledContent("Remaining", value: String(format: "%.1f s", progress.remaining))
                } else if recorder.isFinishing {
                    ProgressView("Saving CSV…")
                } else {
                    Text(recorder.completionMessage ?? "Ready to record")
                }
                LabeledContent("Received rows", value: String(progress.rows))
                LabeledContent("Elapsed", value: String(format: "%.1f s", progress.elapsed))
                if let error = recorder.errorMessage { Text(error).foregroundStyle(.red) }
            }

            Section {
                if recorder.savedFiles.isEmpty {
                    Text("Completed recordings appear here.").foregroundStyle(.secondary)
                }
                ForEach(recorder.savedFiles, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(url.lastPathComponent).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    }.padding(.vertical, 4)
                }
            } header: { Text("Saved Recordings") } footer: {
                Text("Export to Files, AirDrop, or another app. Files contain sensor values, device and phone timing, validity flags, raw bytes, and any packet decode errors.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("IMU Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { durationFocused = false }
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                let latest = recorder.progress
                if latest != progress { progress = latest }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
}
