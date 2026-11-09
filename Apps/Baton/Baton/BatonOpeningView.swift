import SwiftUI

/// A brief branding transition, independent of radio or connection readiness.
struct BatonOpeningView: View {
    @State private var isOpening = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Construct the real app immediately so initialization can run underneath.
            PracticeView()
                .allowsHitTesting(!isOpening)
                .accessibilityHidden(isOpening)

            if isOpening {
                OpeningNoteView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .statusBarHidden(isOpening)
        .task(id: scenePhase) {
            guard isOpening, scenePhase == .active else { return }
            // A short presentation interval, never a wait for Bluetooth permission,
            // a connected baton or network access. Cancellation preserves the cover.
            do { try await Task.sleep(for: .milliseconds(1400)) }
            catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                isOpening = false
            }
        }
    }
}

private struct OpeningNoteView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var spinning = false

    var body: some View {
        ZStack {
            BatonTheme.ultramarine.ignoresSafeArea()
            Image(systemName: "music.note")
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                .animation(reduceMotion || scenePhase != .active ? nil :
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: spinning && !reduceMotion && scenePhase == .active)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Musical Baton")
        .onAppear { spinning = scenePhase == .active }
        .onChange(of: scenePhase) { _, phase in spinning = phase == .active }
        .onChange(of: reduceMotion) { _, _ in spinning = scenePhase == .active }
    }
}
