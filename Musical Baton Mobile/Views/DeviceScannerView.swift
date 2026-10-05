import CoreBluetooth
import SwiftUI

struct DeviceScannerView: View {
    let manager: BLEManager
    @State private var searchText = ""
    @AppStorage("scanner.includeUnnamed") private var includeUnnamed = false
    @AppStorage("scanner.connectableOnly") private var connectableOnly = true

    private var filteredDevices: [BLEDevice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.devices.filter { device in
            (includeUnnamed || device.hasKnownName)
                && (!connectableOnly || device.isConnectable)
                && (query.isEmpty || ([device.name, device.id.uuidString] + device.advertisedServiceUUIDs)
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        List {
            Section {
                Label(manager.bluetoothStatus, systemImage: manager.bluetoothState == .poweredOn ? "antenna.radiowaves.left.and.right" : "exclamationmark.circle")
                    .foregroundStyle(manager.bluetoothState == .poweredOn ? Color.primary : Color.secondary)
                Button(manager.isScanning ? "Stop Scan" : "Scan for Devices") {
                    if manager.isScanning { manager.stopScanning() }
                    else { manager.startScanning() }
                }
                .disabled(manager.bluetoothState != .poweredOn || manager.activeDevice != nil)
                if let device = manager.activeDevice {
                    HStack {
                        ProgressView()
                        Text("\(manager.isDisconnecting ? "Disconnecting from" : "Connecting to") \(device.name)…")
                        Spacer()
                        Button("Cancel") { manager.disconnect() }
                            .disabled(manager.isDisconnecting)
                    }
                }
            } header: { Text("Bluetooth") } footer: {
                Text("Triple-click the baton button to start its 60-second advertising window, then scan and connect.")
            }

            Section {
                Toggle("Include unnamed devices", isOn: $includeUnnamed)
                Toggle("Connectable devices only", isOn: $connectableOnly)
            } header: { Text("Filters") } footer: {
                Text("Search by name, device ID, or advertised service UUID. Some devices do not advertise a name; include unnamed devices to see them.")
            }

            Section("Nearby Devices (\(filteredDevices.count) of \(manager.devices.count))") {
                if filteredDevices.isEmpty {
                    if manager.devices.isEmpty {
                        Text(manager.isScanning ? "Searching for nearby BLE devices…" : "Tap Scan to find nearby BLE devices.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No devices match your search and filters.")
                            if !includeUnnamed {
                                Text("If your baton appears as Unknown Device, turn on Include unnamed devices.")
                            }
                            Button("Show All Devices") {
                                searchText = ""
                                includeUnnamed = true
                                connectableOnly = false
                            }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ForEach(filteredDevices) { device in
                    Button { manager.connect(to: device) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(device.name).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                Text(device.isConnectable ? "Connect" : "Not connectable")
                                    .font(.subheadline)
                            }
                            Text(device.rssi == 127 ? "RSSI unavailable" : "RSSI: \(device.rssi) dBm")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(device.id.uuidString)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            if !device.advertisedServiceUUIDs.isEmpty {
                                Text("Advertised services: \(device.advertisedServiceUUIDs.joined(separator: ", "))")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(manager.activeDevice != nil || manager.bluetoothState != .poweredOn || !device.isConnectable)
                }
            }
            Section {
                NavigationLink("BLE Event Log") { TerminalView(manager: manager).padding() }
            }
        }
        .navigationTitle("Smart Baton BLE")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or UUID")
        .scrollDismissesKeyboard(.interactively)
    }
}
