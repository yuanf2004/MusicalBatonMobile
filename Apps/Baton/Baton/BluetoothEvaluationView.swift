import SwiftUI

struct BluetoothEvaluationView: View {
    let manager: BLEManager
    @State private var file: URL?
    @State private var exportError: String?
    private var run: BluetoothEvaluation { manager.linkEvaluation }

    var body: some View {
        Form {
            Section {
                if run.running {
                    Text("Collecting beat-event measurements")
                    Button("Finish evaluation") { run.stop() }
                } else {
                    Button("Start new live evaluation") { file = nil; run.begin("Live baton") }
                        .disabled(!manager.isConnected)
                    Button("Load simulated run") { file = nil; run.demo() }
                }
            } footer: {
                Text("This evaluation measures beat notifications only: received events, sequence gaps, and phone arrival spacing. It does not measure motion data or read round trips.")
            }
            if !run.running && !run.title.isEmpty {
                Section(run.title) {
                    let beats = run.rows.filter { $0.kind == "beat" }
                    let gaps = beats.reduce(0) { $0 + $1.gap }
                    Text("\(beats.count) beat events received")
                    Text("\(gaps) missing or lost beat events")
                    if let first = beats.first, let last = beats.last, last.phone > first.phone {
                        Text(String(format: "%.1f ms mean arrival spacing", beats.dropFirst().compactMap(\.milliseconds).reduce(0, +) / Double(max(1, beats.dropFirst().compactMap(\.milliseconds).count))))
                    }
                    Text("One-way PCB → phone latency requires synchronized PCB and phone clocks; the CSV preserves both timestamps for that calculation.").font(.caption)
                }
                Section {
                    if let file { ShareLink("Share evaluation CSV", item: file) }
                    else {
                        Button("Prepare CSV") {
                            do { file = try run.export(); exportError = nil }
                            catch { exportError = error.localizedDescription }
                        }.disabled(run.rows.isEmpty)
                    }
                    if let exportError { Text(exportError) }
                }
            }
        }.batonPage("Bluetooth Evaluation")
    }
}
