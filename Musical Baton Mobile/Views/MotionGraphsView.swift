import Charts
import SwiftUI

struct MotionGraphsView: View {
    let manager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var windowSeconds = 30.0

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
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func graphContent(_ model: BLECharacteristic) -> some View {
        let samples = model.motionHistory.visibleSamples(seconds: windowSeconds)
        let latestTime = Double(model.motionHistory.samples.last?.elapsedMilliseconds ?? 0) / 1000
        let accelRange = yRange(samples, acceleration: true)
        let gyroRange = yRange(samples, acceleration: false)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Notifications", isOn: Binding(
                        get: { model.isNotifying },
                        set: { manager.setNotifications($0, for: model) }
                    ))
                    .disabled(model.notificationPending || manager.isDisconnecting)
                    Toggle("Live motion parsing", isOn: Binding(
                        get: { model.isMotionParsingEnabled },
                        set: { manager.setMotionParsing($0, for: model) }
                    ))
                    .disabled(manager.isDisconnecting)
                    Picker("Visible time window", selection: $windowSeconds) {
                        Text("10 s").tag(10.0)
                        Text("30 s").tag(30.0)
                        Text("60 s").tag(60.0)
                    }.pickerStyle(.segmented)
                    Text("Device time · latest packet = 0 s. Each dot is a received sample; firmware currently sends about every 200 ms.")
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
                    Button("Clear Graphs") { model.motionHistory = MotionHistory() }
                        .font(.subheadline)
                }
                ForEach(MotionChannel.allCases) { channel in
                    MotionAxisChart(channel: channel, samples: samples, latestPacket: model.motionPacket ?? model.motionHistory.samples.last?.packet,
                                    latestTime: latestTime, windowSeconds: windowSeconds,
                                    yRange: channel.isAcceleration ? accelRange : gyroRange)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            packetStatus(model)
        }
    }

    // Share a symmetric scale across XYZ within each sensor group for comparison.
    private func yRange(_ samples: [MotionHistory.Sample], acceleration: Bool) -> ClosedRange<Double> {
        let channels = MotionChannel.allCases.filter { $0.isAcceleration == acceleration }
        let largest = samples.flatMap { sample in channels.compactMap { $0.value(in: sample.packet) } }
            .map { abs($0) }.max() ?? 0
        let extent = max(acceleration ? 1000.0 : 10.0, largest * 1.1)
        return -extent...extent
    }

    private func packetStatus(_ model: BLECharacteristic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let packet = model.motionPacket ?? model.motionHistory.samples.last?.packet {
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
                    Text("Received: \(model.motionHistory.receivedCount)")
                    Spacer()
                    Text(model.motionHistory.lastIntervalMilliseconds.map { "Interval: \($0) ms" } ?? "Interval: —")
                }.font(.caption.monospacedDigit())
                Text("v\(packet.version) · Flags 0x\(String(format: "%02X", packet.flags)) · Accel \(packet.accelerationValid ? "valid" : "invalid") · Gyro \(packet.gyroscopeValid ? "valid" : "invalid")")
                    .font(.caption)
                Text("Time synced: \(packet.timeSynchronized ? "yes" : "no") · Clock resets: \(model.motionHistory.clockResetCount)")
                    .font(.caption).foregroundStyle(.secondary)
                if model.motionDecodeError != nil {
                    Text("Showing the last successfully decoded packet.").font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(model.isMotionParsingEnabled ? "Waiting for a valid motion packet…" : "Motion parsing is off")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

private struct MotionAxisChart: View {
    let channel: MotionChannel
    let samples: [MotionHistory.Sample]
    let latestPacket: BatonMotionPacket?
    let latestTime: Double
    let windowSeconds: Double
    let yRange: ClosedRange<Double>

    private var color: Color {
        switch channel.axis {
        case "X": .red
        case "Y": .green
        default: .blue
        }
    }

    private var latestValue: String {
        guard let latestPacket, let value = channel.value(in: latestPacket) else { return "—" }
        return String(format: channel.isAcceleration ? "%.0f %@" : "%.1f %@", value, channel.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(channel.title).font(.subheadline.bold())
                Spacer()
                Text(latestValue).font(.subheadline.monospacedDigit()).foregroundStyle(color)
            }
            Chart {
                RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Color.secondary.opacity(0.3))
                ForEach(samples) { sample in
                    if let value = channel.value(in: sample.packet) {
                        let time = Double(sample.elapsedMilliseconds) / 1000 - latestTime
                        LineMark(x: .value("Time", time), y: .value(channel.unit, value),
                                 series: .value("Continuous segment", channel.segment(in: sample)))
                            .foregroundStyle(color)
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Time", time), y: .value(channel.unit, value))
                            .foregroundStyle(color).symbolSize(8)
                    }
                }
            }
            .chartXScale(domain: -windowSeconds...0.0)
            .chartYScale(domain: yRange)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel(channel.unit)
            .chartLegend(.hidden)
            .frame(height: 125)
            .accessibilityLabel("\(channel.title) over the last \(Int(windowSeconds)) seconds")
            if !samples.contains(where: { channel.value(in: $0.packet) != nil }) {
                Text("No valid \(channel.title.lowercased()) samples in this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
