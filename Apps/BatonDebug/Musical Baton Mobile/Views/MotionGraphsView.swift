import SwiftUI

struct MotionGraphsView: View {
    let manager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowSeconds = 30.0
    @State private var snapshot = MotionGraphSnapshot()

    var body: some View {
        Group {
            if let model = manager.batonMotionCharacteristic {
                graphContent(model)
            } else {
                ContentUnavailableView("Motion characteristic unavailable", systemImage: "waveform.path.ecg",
                                       description: Text("Waiting for the baton motion service to be discovered."))
            }
        }
        .navigationTitle("Live Motion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func graphContent(_ model: BLECharacteristic) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MotionGraphControls(manager: manager, model: model, windowSeconds: $windowSeconds)
                ForEach(snapshot.traces) { trace in
                    MotionAxisChart(trace: trace, windowSeconds: windowSeconds)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { packetStatus }
        .task(id: RefreshTaskID(modelID: model.id, windowSeconds: windowSeconds, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            var previousRevision: Revision?
            while !Task.isCancelled {
                // Read the live model in the task, not the chart body. Packets can
                // arrive at 50+ Hz without invalidating six graph views each time.
                let revision = Revision(count: model.motionHistory.receivedCount,
                                        sampleCount: model.motionHistory.samples.count,
                                        parsing: model.isMotionParsingEnabled,
                                        error: model.motionDecodeError ?? model.error)
                if revision != previousRevision {
                    snapshot = MotionGraphSnapshot(history: model.motionHistory, latestPacket: model.motionPacket,
                                                   parsingEnabled: model.isMotionParsingEnabled,
                                                   errorMessage: model.motionDecodeError ?? model.error,
                                                   windowSeconds: windowSeconds)
                    previousRevision = revision
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    private struct RefreshTaskID: Hashable {
        let modelID: UUID
        let windowSeconds: Double
        let active: Bool
    }
    private struct Revision: Equatable {
        let count: UInt64
        let sampleCount: Int
        let parsing: Bool
        let error: String?
    }

    private var packetStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let packet = snapshot.latestPacket {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Sequence").font(.caption).foregroundStyle(.secondary)
                        Text(String(packet.sequence)).font(.headline.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Device uptime").font(.caption).foregroundStyle(.secondary)
                        Text("\(packet.uptimeMilliseconds) ms").font(.headline.monospacedDigit())
                    }
                }
                HStack {
                    Text("Received: \(snapshot.receivedCount)")
                    Spacer()
                    Text(snapshot.intervalMilliseconds.map { "Interval: \($0) ms" } ?? "Interval: —")
                }.font(.caption.monospacedDigit())
                Text("v\(packet.version) · Flags 0x\(String(format: "%02X", packet.flags)) · Accel \(packet.accelerationValid ? "valid" : "invalid") · Gyro \(packet.gyroscopeValid ? "valid" : "invalid")")
                    .font(.caption)
                Text("Time synced: \(packet.timeSynchronized ? "yes" : "no") · Clock resets: \(snapshot.clockResetCount)")
                    .font(.caption).foregroundStyle(.secondary)
                if snapshot.errorMessage != nil {
                    Text("Showing the last successfully decoded packet.").font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(snapshot.parsingEnabled ? "Waiting for a valid motion packet…" : "Motion parsing is off")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

// Controls observe their own state; incoming samples do not rebuild chart data.
private struct MotionGraphControls: View {
    let manager: BLEManager
    let model: BLECharacteristic
    @Binding var windowSeconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Notifications", isOn: Binding(
                get: { model.isNotifying }, set: { manager.setNotifications($0, for: model) }
            ))
            .disabled(model.notificationPending || manager.isDisconnecting)
            Toggle("Live motion parsing", isOn: Binding(
                get: { model.isMotionParsingEnabled }, set: { manager.setMotionParsing($0, for: model) }
            ))
            .disabled(manager.isDisconnecting)
            Picker("Visible time window", selection: $windowSeconds) {
                Text("10 s").tag(10.0)
                Text("30 s").tag(30.0)
                Text("60 s").tag(60.0)
            }.pickerStyle(.segmented)
            Text("Device time · latest packet = 0 s. Graphs refresh up to 10 times/s; displayed traces preserve peaks while recording continues at the incoming packet rate.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.isMotionParsingEnabled {
                Text("Enable Notifications and Live motion parsing to plot incoming packets.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !model.isNotifying {
                Text("Notifications are off. Reads still plot values; enable Notifications for a live stream.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.motionDecodeError ?? model.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Button("Clear Graphs") { model.motionHistory = MotionHistory() }.font(.subheadline)
        }
    }
}

private struct MotionAxisChart: View {
    let trace: MotionGraphSnapshot.Trace
    let windowSeconds: Double

    private var color: Color {
        switch trace.channel.axis {
        case "X": .red
        case "Y": .green
        default: .blue
        }
    }
    private var latestValue: String {
        guard let value = trace.latestValue else { return "—" }
        return String(format: trace.channel.isAcceleration ? "%.0f %@" : "%.1f %@", value, trace.channel.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trace.channel.title).font(.subheadline.bold())
                Spacer()
                Text(latestValue).font(.subheadline.monospacedDigit()).foregroundStyle(color)
            }
            Canvas { context, size in
                let plot = CGRect(x: 52, y: 8, width: max(1, size.width - 62), height: max(1, size.height - 34))
                let extent = trace.yRange.upperBound
                func position(_ point: MotionGraphSnapshot.Point) -> CGPoint {
                    CGPoint(x: plot.minX + (point.time + windowSeconds) / windowSeconds * plot.width,
                            y: plot.midY - point.value / extent * plot.height / 2)
                }
                var grid = Path()
                for index in 0...4 {
                    let fraction = Double(index) / 4
                    let x = plot.minX + fraction * plot.width
                    grid.move(to: CGPoint(x: x, y: plot.minY))
                    grid.addLine(to: CGPoint(x: x, y: plot.maxY))
                    let label = String(format: "%.1f", -windowSeconds + fraction * windowSeconds)
                    context.draw(Text(label).font(.system(size: 10)).foregroundColor(.secondary),
                                 at: CGPoint(x: x, y: plot.maxY + 6), anchor: .top)
                }
                for value in [-extent, 0, extent] {
                    let y = plot.midY - value / extent * plot.height / 2
                    grid.move(to: CGPoint(x: plot.minX, y: y))
                    grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                    let label = String(format: abs(value) >= 100 ? "%.0f" : "%.1f", value)
                    context.draw(Text(label).font(.system(size: 10)).foregroundColor(.secondary),
                                 at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing)
                }
                context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
                var paths = Path()
                for segment in trace.segments {
                    guard let first = segment.first else { continue }
                    if segment.count == 1 {
                        let point = position(first)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                                     with: .color(color))
                    } else {
                        paths.move(to: position(first))
                        for point in segment.dropFirst() { paths.addLine(to: position(point)) }
                    }
                }
                context.stroke(paths, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .frame(height: 125)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(trace.channel.title) over the last \(Int(windowSeconds)) seconds")
            .accessibilityValue("Latest value \(latestValue)")
            Text("Time (s) · Value (\(trace.channel.unit))").font(.caption2).foregroundStyle(.secondary)
            if trace.segments.isEmpty {
                Text("No valid \(trace.channel.title.lowercased()) samples in this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
