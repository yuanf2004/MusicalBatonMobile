import AVFoundation
import Observation

@MainActor
@Observable
final class SoundPreview {
    private(set) var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ownsSession = false
    @ObservationIgnored private var cleanup: Task<Void, Never>?

    func play(_ voice: ClickVoice) {
        stop()
        error = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ownsSession = true
            let sound = try AVAudioPlayer(data: BeatSound.wavData(voice: voice))
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
