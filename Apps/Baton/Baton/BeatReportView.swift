import SwiftUI
import UIKit

private extension BeatDetectionReport.Label {
    var color: Color {
        switch self {
        case .matched: Color(red: 0.16, green: 0.55, blue: 0.33)
        case .missed: Color(red: 0.85, green: 0.45, blue: 0.05)
        case .duplicate: Color(red: 0.45, green: 0.30, blue: 0.75)
        case .falseTrigger: Color(red: 0.80, green: 0.15, blue: 0.20)
        }
    }
}

/// Shows the detection report and shares it as PDF or CSV through the share
/// sheet (Save to Files, Messages, Google Drive and other installed targets).
struct BeatReportView: View {
    let report: BeatDetectionReport
    @State private var shareItem: ShareURL?
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            BeatReportContent(report: report).padding()
        }
        .background(BatonTheme.canvas)
        .navigationTitle("Beat Report").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("PDF Report", systemImage: "doc.richtext") { export { try writePDF() } }
                    Button("CSV Beat Data", systemImage: "tablecells") { export { try writeCSV() } }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }
        .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
        .alert("Could not export report", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    private func export(_ make: () throws -> URL) {
        do { shareItem = ShareURL(url: try make()) } catch { exportError = error.localizedDescription }
    }

    private func fileURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(BeatDetectionReport.safeFileStem(report.recordingName)) Report.\(ext)")
    }

    private func writeCSV() throws -> URL {
        let url = fileURL("csv")
        try Data(report.csv().utf8).write(to: url, options: .atomic)
        return url
    }

    /// Renders the same content as one US-letter-wide page sized to fit.
    private func writePDF() throws -> URL {
        let url = fileURL("pdf")
        let renderer = ImageRenderer(content: BeatReportContent(report: report)
            .padding(36).frame(width: 612).background(Color.white).environment(\.colorScheme, .light))
        var thrown: Error?
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
                thrown = CocoaError(.fileWriteUnknown); return
            }
            context.beginPDFPage(nil); draw(context); context.endPDFPage(); context.closePDF()
        }
        if let thrown { throw thrown }
        return url
    }
}

private struct ShareURL: Identifiable { let id = UUID(); let url: URL }

struct BeatReportContent: View {
    let report: BeatDetectionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            section("Summary") {
                grid([
                    ("Beat accuracy", pct(report.beatAccuracy)),
                    ("Missed", pct(report.missedPercent)),
                    ("Duplicates", pct(report.duplicatePercent)),
                    ("False triggers", pct(report.falseTriggerPercent)),
                    ("Avg timing offset", ms(report.averageOffsetMilliseconds, signed: true)),
                    ("Timing consistency", msOpt(report.timingConsistencyMilliseconds).map { "±" + $0 } ?? "—"),
                    ("Beats within 50 ms", pct(report.withinTolerancePercent)),
                ])
                Text("Edited beats are treated as correct. Beats match within \(BeatDetectionReport.matchWindowMicroseconds / 1000) ms; a positive offset means the baton was late.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Beat Detection") {
                grid([
                    ("Beats (detected → edited)", "\(report.originalCount) → \(report.finalCount)"),
                    ("Net count difference", pct(report.netCountDifference)),
                    ("Matched", "\(report.matched)"),
                    ("Missed", "\(report.missed)"),
                    ("Duplicates", "\(report.duplicates)"),
                    ("False triggers", "\(report.falseTriggers)"),
                ])
            }
            section("Timeline") { BeatReportTimeline(report: report).frame(height: 90); legend }
            section("Timing Offsets") { OffsetHistogram(report: report).frame(height: 120) }
            section("Tempo") {
                grid([
                    ("Detected tempo", bpm(report.originalTempo)),
                    ("Edited tempo", bpm(report.finalTempo)),
                    ("Tempo difference", pct(report.tempoDifferencePercent)),
                    ("Steadiness (detected)", msOpt(report.originalSteadinessMilliseconds).map { "±" + $0 } ?? "—"),
                    ("Steadiness (edited)", msOpt(report.finalSteadinessMilliseconds).map { "±" + $0 } ?? "—"),
                ])
            }
            if !report.measures.isEmpty {
                section("Accuracy by Measure") {
                    ForEach(report.measures, id: \.measure) { row in
                        HStack {
                            Text("Measure \(row.measure)").frame(width: 100, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(Color.secondary.opacity(0.2))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(BeatDetectionReport.Label.matched.color)
                                            .frame(width: proxy.size.width * CGFloat((row.accuracy ?? 0) / 100))
                                    }
                            }.frame(height: 10)
                            Text(pct(row.accuracy)).monospacedDigit().frame(width: 56, alignment: .trailing)
                        }.font(.caption)
                    }
                }
            }
            section("Edits") {
                grid([
                    ("Beats added", "\(report.beatsAdded)"),
                    ("Beats deleted", "\(report.beatsDeleted)"),
                    ("Undos", "\(report.undoCount)"),
                    ("Edit rate", pct(report.editRatePercent)),
                ])
            }
        }
        .foregroundStyle(Color.primary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.recordingName).font(BatonTheme.serif(26, relativeTo: .title2))
            Text(report.recordingDate, format: .dateTime.month().day().year().hour().minute())
            Text("Duration \(String(format: "%d:%02d", Int(report.duration) / 60, Int(report.duration) % 60)) · Sensitivity: \(report.sensitivity?.title ?? "None (touchpad)")")
        }.font(.subheadline)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(BeatDetectionReport.Label.allCases, id: \.self) { label in
                HStack(spacing: 4) { Circle().fill(label.color).frame(width: 8, height: 8); Text(label.title) }
            }
        }.font(.caption2)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func grid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    Text(rows[i].0).foregroundStyle(.secondary)
                    Text(rows[i].1).monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }.font(.callout)
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0) } ?? "—" }
    private func bpm(_ v: Double?) -> String { v.map { String(format: "%.1f bpm", $0) } ?? "—" }
    private func msOpt(_ v: Double?, signed: Bool = false) -> String? {
        v.map { String(format: signed ? "%+.1f ms" : "%.1f ms", $0) }
    }
    private func ms(_ v: Double?, signed: Bool = false) -> String { msOpt(v, signed: signed) ?? "—" }
}

/// Detected beats on the top row, edited beats on the bottom row, relative time.
private struct BeatReportTimeline: View {
    let report: BeatDetectionReport

    var body: some View {
        Canvas { context, size in
            let end = max(report.duration, 0.001)
            let labelWidth: CGFloat = 64
            let width = size.width - labelWidth - 6
            for (row, source) in [BeatDetectionReport.Source.original, .final].enumerated() {
                let y = size.height * (row == 0 ? 0.3 : 0.75)
                context.draw(Text(row == 0 ? "Detected" : "Edited").font(.caption2), at: CGPoint(x: 0, y: y), anchor: .leading)
                var line = Path(); line.move(to: CGPoint(x: labelWidth, y: y)); line.addLine(to: CGPoint(x: labelWidth + width, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                for beat in report.labeled where beat.source == source {
                    let x = labelWidth + width * CGFloat(Double(beat.elapsedMicroseconds) / 1_000_000 / end)
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 7, width: 6, height: 14)), with: .color(beat.label.color))
                }
            }
            context.draw(Text("0 s").font(.caption2), at: CGPoint(x: labelWidth, y: size.height), anchor: .bottomLeading)
            context.draw(Text(String(format: "%.1f s", end)).font(.caption2), at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
        }
        .accessibilityLabel("Beat timeline: \(report.matched) matched, \(report.missed) missed, \(report.duplicates) duplicate, \(report.falseTriggers) false trigger")
    }
}

/// 10 ms bins across ±125 ms with the average offset marked.
private struct OffsetHistogram: View {
    let report: BeatDetectionReport

    var body: some View {
        Canvas { context, size in
            let window = Double(BeatDetectionReport.matchWindowMicroseconds) / 1000
            let binWidth = 10.0
            let bins = Int((2 * window / binWidth).rounded(.up))
            var counts = [Int](repeating: 0, count: bins)
            for offset in report.offsetsMicroseconds {
                let index = Int(((Double(offset) / 1000 + window) / binWidth).rounded(.down))
                counts[min(bins - 1, max(0, index))] += 1
            }
            let chartHeight = size.height - 16
            let peak = max(1, counts.max() ?? 1)
            let slot = size.width / CGFloat(bins)
            for (i, count) in counts.enumerated() where count > 0 {
                let h = chartHeight * CGFloat(count) / CGFloat(peak)
                context.fill(Path(CGRect(x: CGFloat(i) * slot + 1, y: chartHeight - h, width: slot - 2, height: h)),
                             with: .color(BeatDetectionReport.Label.matched.color))
            }
            func x(_ ms: Double) -> CGFloat { size.width * CGFloat((ms + window) / (2 * window)) }
            var zero = Path(); zero.move(to: CGPoint(x: x(0), y: 0)); zero.addLine(to: CGPoint(x: x(0), y: chartHeight))
            context.stroke(zero, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let avg = report.averageOffsetMilliseconds {
                var mark = Path(); mark.move(to: CGPoint(x: x(avg), y: 0)); mark.addLine(to: CGPoint(x: x(avg), y: chartHeight))
                context.stroke(mark, with: .color(.red), lineWidth: 2)
                context.draw(Text(String(format: "avg %+.1f ms", avg)).font(.caption2).foregroundStyle(.red),
                             at: CGPoint(x: min(size.width - 40, max(40, x(avg))), y: 0), anchor: .top)
            }
            context.draw(Text("−\(Int(window)) ms (early)").font(.caption2), at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
            context.draw(Text("+\(Int(window)) ms (late)").font(.caption2), at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
        }
        .accessibilityLabel(report.offsetsMicroseconds.isEmpty ? "No matched beats" : "Histogram of timing offsets for \(report.offsetsMicroseconds.count) matched beats")
    }
}
