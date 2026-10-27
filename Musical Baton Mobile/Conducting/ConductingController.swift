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
    private(set) var beatInMeasure = 0
    private(set) var needsDownbeat = false
    @ObservationIgnored private var measure = MeasureCounter()
    private(set) var status = "Enable Conducting Mode to play a click for each detected stop."
    private(set) var error: String?
    @ObservationIgnored private var gate = BeatEventGate()
    @ObservationIgnored private var players: [AVAudioPlayer] = []
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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            players = []
            for (voice, accented) in [(profile.downbeatSound, true), (profile.otherBeatSound, false)] {
                let prepared = try AVAudioPlayer(data: BeatSound.wavData(voice: voice, accented: accented))
                guard prepared.prepareToPlay() else { throw AudioError.prepare }
                players.append(prepared)
            }
            activeProfile = profile
            beatCount = 0
            beatInMeasure = 0
            needsDownbeat = false
            measure.reset()
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
        status = ready ? "Ready. Make beat 1 next; each detected beat advances the measure."
                       : "Applying the profile and enabling beat notifications…"
    }

    func stop(reason: String = "Conducting Mode is off.") {
        let hadAudio = !players.isEmpty || isEnabled
        isEnabled = false
        isReady = false
        players.forEach { $0.stop() }
        players = []
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

    func receive(_ packet: BatonBeatPacket) {
        guard gate.accept(packet), isEnabled, isReady, let profile = activeProfile else { return }
        guard !needsDownbeat, let position = measure.advance(packet, beatsPerMeasure: profile.beatsPerMeasure) else {
            needsDownbeat = true
            status = "A pause or missing event interrupted the count. Tap Next beat is 1 to resume."
            return
        }
        if playClick(downbeat: position == 1) {
            lastBeat = packet
            beatInMeasure = position
            beatCount += 1
        }
    }

    func resetDownbeat() {
        guard isEnabled, isReady else { return }
        measure.reset()
        beatInMeasure = 0
        needsDownbeat = false
        status = "Ready for beat 1. Make the next stroke on your downbeat."
    }

    func testSound(downbeat: Bool = true) {
        guard isEnabled else { return }
        _ = playClick(downbeat: downbeat)
    }

    private func playClick(downbeat: Bool) -> Bool {
        guard players.count == 2 else { return false }
        players.forEach { $0.stop() }
        let player = players[downbeat ? 0 : 1]
        player.currentTime = 0
        guard player.play() else {
            fail("The phone could not play the click. Try enabling the mode again.")
            return false
        }
        return true
    }

    private enum AudioError: LocalizedError {
        case prepare
        var errorDescription: String? { "The phone could not prepare the click sound." }
    }
}
