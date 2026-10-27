import SwiftUI

struct ContentView: View {
    @State private var manager = BLEManager()
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { manager.stopConducting(reason: "App inactive. Enable Conducting Mode when you return.") }
            if phase == .background { manager.imuRecorder.stop(reason: "App entered background") }
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
