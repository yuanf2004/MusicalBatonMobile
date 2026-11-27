import SwiftUI
import UIKit

/// Shows the detection report and shares it as PDF or CSV through the share
/// sheet (Save to Files, Messages, Google Drive and other installed targets).
struct BeatReportView: View {
    let report: BeatDetectionReport
    @State private var shareItem: ShareURL?
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            BeatReportContent(report: report, showsHelp: true).padding()
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
        let renderer = ImageRenderer(content: BeatReportContent(report: report, showsHelp: false)
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
    /// Help buttons are interactive, so the exported PDF leaves them out.
    var showsHelp = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            section("Beat Detection") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Precision", pct(report.precision), help: (
                        "Precision",
                        "Of the beats the baton played, the share that were real beats: matched beats ÷ beats played × 100. Beats you added in the editor were never played, so they don't count toward precision. Extra or accidental clicks lower it."))
                    row("Recall", pct(report.recall), help: (
                        "Recall",
                        "Of the real beats in your edited recording, the share the baton played: matched beats ÷ edited beats × 100. Beats you had to add lower it."))
                    row("Beats (played → edited)", "\(report.originalCount) → \(report.finalCount)")
                    row("Net beat count change", netChange)
                    row("Matched", "\(report.matched)")
                    row("Missed (added in editor)", "\(report.missed)")
                    row("Extra (played, not real)", "\(report.falsePositives)")
                }.font(.callout)
                Text("Edited beats are treated as correct. A played beat matches an edited beat within \(BeatDetectionReport.matchWindowMicroseconds / 1000) ms.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Timing") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Average offset magnitude", report.averageOffsetMagnitudeMilliseconds.map { String(format: "%.1f ms", $0) } ?? "—")
                    row("Beats within 50 ms", pct(report.withinTolerancePercent))
                }.font(.callout)
            }
            section("Edits") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Beats added", "\(report.beatsAdded)")
                    row("Beats deleted", "\(report.beatsDeleted)")
                }.font(.callout)
            }
        }
        .foregroundStyle(Color.primary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.recordingName).font(BatonTheme.serif(26, relativeTo: .title2))
            Text(report.recordingDate, format: .dateTime.month().day().year().hour().minute())
            Text("Duration \(clock(report.duration))")
        }.font(.subheadline)
    }

    private var netChange: String {
        let n = report.netCountChange
        let beats = "\(n > 0 ? "+" : "")\(n) beat\(abs(n) == 1 ? "" : "s")"
        return report.netCountChangePercent.map { beats + String(format: " (%+.1f%%)", $0) } ?? beats
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String, help: (String, String)? = nil) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                if showsHelp, let help { TermHelpButton(title: help.0, message: help.1) }
            }
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0) } ?? "—" }
    private func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
