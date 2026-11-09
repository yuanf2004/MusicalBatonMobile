import SwiftUI

struct TerminalView: View {
    let manager: BLEManager
    var isExpanded = false
    var isPaused = false
    @Environment(\.scenePhase) private var scenePhase
    var onToggleExpansion: (() -> Void)? = nil
    @State private var autoScroll = true
    @State private var displayedLogs: [BLELogEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Terminal").font(.headline)
                Spacer()
                Toggle("Follow", isOn: $autoScroll).fixedSize().font(.caption)
                Button("Clear") {
                    manager.clearLogs()
                    displayedLogs.removeAll()
                }.font(.subheadline)
                if let onToggleExpansion {
                    Button(action: onToggleExpansion) {
                        Label(isExpanded ? "Collapse Terminal" : "Expand Terminal",
                              systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityHint(isExpanded ? "Return to services while staying connected" : "Show the live terminal fullscreen while staying connected")
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if displayedLogs.isEmpty {
                            Text("BLE events and raw received bytes appear here.").foregroundStyle(.secondary)
                        }
                        ForEach(displayedLogs) { entry in
                            Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.message)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: displayedLogs.last?.id) { _, latest in
                    if autoScroll, let latest { proxy.scrollTo(latest, anchor: .bottom) }
                }
                .onChange(of: autoScroll) { _, follow in
                    if follow, let latest = displayedLogs.last?.id { proxy.scrollTo(latest, anchor: .bottom) }
                }
                .onAppear {
                    if autoScroll, let latest = displayedLogs.last?.id { proxy.scrollTo(latest, anchor: .bottom) }
                }
            }
        }
        .task(id: isPaused || scenePhase != .active) {
            guard !isPaused, scenePhase == .active else { return }
            while !Task.isCancelled {
                if manager.logs.last?.id != displayedLogs.last?.id || manager.logs.count != displayedLogs.count {
                    displayedLogs = manager.logs
                }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
}
