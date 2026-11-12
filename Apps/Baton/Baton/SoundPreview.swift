import AVFoundation
import Observation

@MainActor
@Observable
final class SoundPreview {
    private(set) var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ownsSession = false
    @ObservationIgnored private var cleanup: Task<Void, Never>?

    func play(_ voice: ClickVoice, accented: Bool = false) {
        stop()
        error = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ownsSession = true
            let sound = try AVAudioPlayer(data: BeatSound.wavData(voice: voice, accented: accented))
            player = sound
            sound.prepareToPlay()
            guard sound.play() else { throw BeatAudioEngine.AudioError.prepare }
            cleanup = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                self?.stop()
            }
        } catch {
            stop()
            self.error = "Could not preview this sound. \(error.localizedDescription)"
        }
    }
    func stop() {
        cleanup?.cancel()
        cleanup = nil
        let hadSession = ownsSession
        ownsSession = false
        player?.stop()
        player = nil
        if hadSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

// Keep touchpad audio ready between taps; no decoding or session setup per beat.
@MainActor
@Observable
final class TouchpadAudio {
    private(set) var error: String?
    private var voice: ClickVoice = .click
    @ObservationIgnored private var engine: BeatAudioEngine?
    @ObservationIgnored private var ownsSession = false

    func prepare(_ voice: ClickVoice) {
        self.voice = voice
        stop()
        error = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            ownsSession = true
            let engine = try BeatAudioEngine(voice: voice)
            try engine.start()
            self.engine = engine
        } catch {
            stop()
            self.error = "Could not prepare touchpad audio. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func play(accented: Bool = false) -> Bool {
        if engine?.trigger(accented: accented) == true {
            error = nil
            return true
        }
        // Recover from an invalidated audio graph without requiring a sound change.
        prepare(voice)
        guard engine?.trigger(accented: accented) == true else {
            if error == nil { error = "Could not start touchpad audio. Try again." }
            return false
        }
        error = nil
        return true
    }

    func stop() {
        engine?.stop()
        engine = nil
        if ownsSession {
            ownsSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
