import SwiftUI

struct DeviceDetailView: View {
    let manager: BLEManager
    @State private var isTerminalExpanded = false
    @State private var showingMotionGraphs = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !isTerminalExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(manager.isDisconnecting ? "Disconnecting…" : "Connected", systemImage: "link")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Disconnect", role: .destructive) { manager.disconnect() }
                                .disabled(manager.isDisconnecting)
                        }
                        if let device = manager.activeDevice {
                            Text(device.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if manager.batonMotionCharacteristic != nil {
                            Button { showingMotionGraphs = true } label: {
                                Label("Live Graphs", systemImage: "waveform.path.ecg")
                            }
                            .buttonStyle(.bordered)
                            .disabled(manager.isDisconnecting)
                        }
                    }
                    .padding()
                    List {
                        Section("Services (\(manager.services.count))") {
                            if manager.isDiscoveringServices {
                                ProgressView("Discovering services…")
                            } else if manager.services.isEmpty {
                                Text("No services available. Check the event log for discovery errors.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(manager.services) { service in
                                ServiceView(manager: manager, service: service)
                            }
                        }
                    }
                    .disabled(manager.isDisconnecting)
                    Divider()
                }
                TerminalView(manager: manager, isExpanded: isTerminalExpanded,
                             onToggleExpansion: { isTerminalExpanded.toggle() })
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(height: isTerminalExpanded ? nil : max(130, geometry.size.height * 0.3))
                    .frame(maxHeight: isTerminalExpanded ? .infinity : nil)
            }
        }
        .navigationTitle(manager.activeDevice?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isTerminalExpanded)
        .fullScreenCover(isPresented: $showingMotionGraphs) {
            NavigationStack { MotionGraphsView(manager: manager) }
        }
        .onChange(of: manager.isConnected) { _, connected in
            if !connected { showingMotionGraphs = false }
        }
        .toolbar {
            if isTerminalExpanded {
                ToolbarItem(placement: .topBarLeading) {
                    Label(manager.isDisconnecting ? "Disconnecting…" : "Connected", systemImage: "link")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
