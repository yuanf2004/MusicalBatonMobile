import AVFoundation

// Prepared once per session. Each beat only schedules the same immutable buffer.
// The player stays running between cues; interrupts prevents stale cue queues.
@MainActor
final class BeatAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer

    init(voice: ClickVoice) throws {
        buffer = try Self.makeBuffer(voice: voice)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
    }

    func start() throws {
        player.prepare(withFrameCount: buffer.frameLength)
        engine.prepare()
        try engine.start()
        player.play()
    }

    func trigger() -> Bool {
        guard engine.isRunning, player.isPlaying else { return false }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    func stop() {
        player.stop() // Discards scheduled audio before shutting down the graph.
        engine.stop()
        engine.reset()
    }

    nonisolated static func makeBuffer(voice: ClickVoice) throws -> AVAudioPCMBuffer {
        // BeatSound generates a 44-byte PCM header followed by mono 16-bit LE,
        // 44.1 kHz samples. Keep the existing voice/envelope exactly unchanged.
        let wav = Array(BeatSound.wavData(voice: voice, accented: false))
        let frames = (wav.count - 44) / 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { throw AudioError.prepare }
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames {
            let value = UInt16(wav[44+i*2]) | UInt16(wav[45+i*2]) << 8
            channel[i] = Float(Int16(bitPattern: value)) / 32768
        }
        return buffer
    }

    enum AudioError: LocalizedError {
        case prepare
        var errorDescription: String? { "Could not prepare the beat audio buffer." }
    }
}
