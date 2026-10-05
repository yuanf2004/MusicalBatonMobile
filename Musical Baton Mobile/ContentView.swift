import SwiftUI

struct ContentView: View {
    @State private var manager = BLEManager()
    @State private var showingDevice = false

    var body: some View {
        NavigationStack {
            DeviceScannerView(manager: manager)
                .navigationDestination(isPresented: $showingDevice) {
                    DeviceDetailView(manager: manager)
                }
        }
        .onChange(of: manager.isConnected) { _, connected in
            showingDevice = connected
        }
        .onChange(of: showingDevice) { _, presented in
            if !presented { manager.disconnect() }
        }
        .alert("Bluetooth error", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }
}
