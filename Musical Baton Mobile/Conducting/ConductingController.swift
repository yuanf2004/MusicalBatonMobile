import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ConductingController {
    private(set) var isEnabled = false
    private(set) var isReady = false
    private(set) var beatCount = 0
    private(set) var lastBeat: BatonBeatPacket?
    private(set) var activeProfile: ConductingProfile?
    var filterMode: BeatFilterMode = .gesture
    var strengthThreshold = 50
    private(set) var filteredCount = 0
    private(set) var gestureLabel = "Warming up"
    private(set) var lastFilterReason: String?
    @ObservationIgnored private var gestureFilter: GestureFilter?
    private(set) var status = "Enable Conducting Mode to play filtered beats."
    private(set) var error: String?
    @ObservationIgnored private var gate = BeatEventGate()
    @ObservationIgnored private var audio: BeatAudioEngine?
    private(set) var audioBufferMS: Double = 0
    private(set) var audioOutputMS: Double = 0
    private(set) var audioRoute = "Not active"
    private(set) var callbackToScheduleMS: Double?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  value == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stop(reason: "Audio interrupted. Enable Conducting Mode again when ready.")
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ||
                  value == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stop(reason: "Audio output changed. Enable Conducting Mode again when ready.")
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop(reason: "Audio restarted. Enable Conducting Mode again when ready.")
            }
        })
    }

    func start(profile: ConductingProfile) {
        guard !isEnabled, profile.isValid else { return }
        error = nil
        do {
            gestureFilter = filterMode == .gesture ? GestureFilter(tree: try GestureTree.bundled()) : nil
            gestureLabel = filterMode == .gesture ? "Warming up" : "Off"
            filteredCount = 0
            lastFilterReason = nil
            callbackToScheduleMS = nil
            let session = AVAudioSession.sharedInstance()
            // Exclusive playback gives the system more freedom to honor a short buffer.
            // Enabling Conducting Mode intentionally interrupts other media.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredIOBufferDuration(0.0029)
            try session.setActive(true)
            audio = try BeatAudioEngine(voice: profile.otherBeatSound)
            try audio?.start()
            audioBufferMS = session.ioBufferDuration * 1000
            audioOutputMS = session.outputLatency * 1000
            audioRoute = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
            activeProfile = profile
            beatCount = 0
            lastBeat = nil
            isEnabled = true
            notificationState(ready: false)
        } catch {
            stop(reason: "Could not start sound playback.")
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.error = error.localizedDescription
        }
    }

    func notificationState(ready: Bool) {
        guard isEnabled else { return }
        isReady = ready
        status = ready ? "Ready. Each accepted beat plays one sound."
                       : "Applying sensitivity and enabling notifications…"
    }

    func stop(reason: String = "Conducting Mode is off.") {
        let hadAudio = audio != nil || isEnabled
        isEnabled = false
        isReady = false
        audio?.stop()
        audio = nil
        gestureFilter?.reset()
        gestureLabel = filterMode == .gesture ? "Warming up" : "Off"
        status = reason
        if hadAudio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func fail(_ message: String) {
        stop(reason: "Conducting Mode stopped.")
        error = message
    }

    func resetConnection() {
        stop(reason: "Connect to the baton and enable Conducting Mode.")
        gate = BeatEventGate()
        beatCount = 0
        lastBeat = nil
        error = nil
    }

    func receive(_ packet: BatonBeatPacket, receivedAt: TimeInterval) {
        guard gate.accept(packet), isEnabled, isReady, activeProfile != nil else { return }
        let label = gestureFilter?.currentLabel(at: ProcessInfo.processInfo.systemUptime)
        gestureLabel = filterMode == .gesture ? (label ?? "Warming up") : "Off"
        if let reason = BeatPlaybackPolicy.rejection(strength: packet.strength,
                threshold: strengthThreshold, mode: filterMode, label: label) {
            filteredCount += 1
            lastFilterReason = reason
            return
        }
        lastFilterReason = nil
        if playClick() {
            callbackToScheduleMS = max(0, ProcessInfo.processInfo.systemUptime - receivedAt) * 1000
            lastBeat = packet
            beatCount += 1
        }
    }

    func receiveMotion(_ packet: BatonMotionPacket, receivedAt: TimeInterval) {
        guard isEnabled else { return }
        gestureFilter?.add(packet, receivedAt: receivedAt)
        gestureLabel = filterMode == .gesture ? (gestureFilter?.currentLabel(at: receivedAt) ?? "Warming up") : "Off"
    }

    func testSound() {
        guard isEnabled, isReady else { return }
        _ = playClick()
    }

    private func playClick() -> Bool {
        guard audio?.trigger() == true else {
            fail("The audio engine stopped. Enable Conducting Mode again to restart it.")
            return false
        }
        return true
    }
}
