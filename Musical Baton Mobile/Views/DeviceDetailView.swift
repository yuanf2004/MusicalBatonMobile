import SwiftUI

struct DeviceDetailView: View {
    let manager: BLEManager

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
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
                TerminalView(manager: manager)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(height: max(130, geometry.size.height * 0.3))
            }
        }
        .navigationTitle(manager.activeDevice?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
    }
}
