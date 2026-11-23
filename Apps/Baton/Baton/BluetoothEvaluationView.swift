import SwiftUI
import Charts

struct BluetoothEvaluationView: View {
    let manager: BLEManager
    @State private var file: URL?
    @State private var exportError: String?
    private var run: BluetoothEvaluation { manager.linkEvaluation }

    var body: some View {
        Form {
            Section {
                if run.running {
                    Text("Collecting Bluetooth measurements")
                    Button("Finish evaluation") { run.stop() }
                } else {
                    Button("Start new live evaluation") {
                        file = nil
                        run.begin("Live baton")
                    }.disabled(!manager.isConnected)
                    Button("Load simulated run") { file = nil; run.demo() }
                }
            } footer: {
                Text("Connect the baton to measure practice-control reads. Start practice and conduct to collect beat notifications. Motion notifications depend on the active practice filter. Capture ends at disconnect or 20,000 events.")
            }
            if !run.running && !run.title.isEmpty {
                Section(run.title) {
                    Text("\(run.rows.count) events")
                    ForEach(["beat", "motion"], id: \.self) { stream in
                        streamResult(stream)
                    }
                }
                timingResult
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

    private func streamResult(_ stream: String) -> some View {
        let rows = run.rows.filter { $0.kind == stream }
        let gaps = rows.reduce(0) { $0 + $1.gap }
        let unique = rows.filter { $0.status == "first" || $0.status == "forward" }.count
        let intervals = rows.compactMap(\.milliseconds)
        let elapsed = intervals.reduce(0,+)
        return VStack(alignment: .leading, spacing: 5) {
            Text(stream.capitalized + " notifications").font(.headline)
            Text("\(rows.count) received · \(gaps) missing in sequence")
            if unique > 1 {
                Text(String(format: "Estimated loss %.2f%%", 100 * Double(gaps) / Double(unique + gaps)))
            }
            if elapsed > 0 {
                Text(String(format: "%.1f arrivals/s · %.1f ms mean spacing",
                            Double(intervals.count)*1000/elapsed, elapsed/Double(intervals.count)))
            }
        }
    }

    private var timingResult: some View {
        let times = run.rows.filter { $0.kind == "read" }.compactMap(\.milliseconds).sorted()
        let n = Double(times.count)
        return Section {
            if let min = times.first, let max = times.last {
                let mean = times.reduce(0,+)/n
                let deviation = sqrt(times.reduce(0) { $0 + pow($1-mean,2) }/n)
                LabeledContent("Successful reads", value: "\(times.count)")
                LabeledContent("Mean ± SD", value: String(format: "%.1f ± %.1f ms", mean,deviation))
                LabeledContent("Min / P95 / max", value: String(format: "%.1f / %.1f / %.1f ms", min,times[Int(ceil(0.95*n))-1],max))
                let bins = Dictionary(grouping: times) { Int($0 / 5) }
                Chart(bins.keys.sorted(), id: \.self) { bin in
                    BarMark(xStart: .value("From (ms)", bin*5), xEnd: .value("To (ms)", bin*5+5),
                            y: .value("Reads", bins[bin]?.count ?? 0))
                }.frame(height: 140).chartXAxisLabel("Round trip (ms)")
            } else { Text("No successful practice-control reads") }
        } header: { Text("Read round-trip time") } footer: {
            Text("Includes phone scheduling and baton response time. One-way beat latency requires a separate measurement. Sequence gaps estimate missing app notifications between observed packets.")
        }
    }
}
