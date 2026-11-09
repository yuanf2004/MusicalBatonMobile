import AVFoundation
import Foundation

@main
struct AudioBufferChecks {
    static func main() throws {
        for voice in ClickVoice.allCases {
            let wav = Array(BeatSound.wavData(voice: voice, accented: false))
            let buffer = try BeatAudioEngine.makeBuffer(voice: voice)
            precondition(buffer.format.sampleRate == 44100 && buffer.format.channelCount == 1)
            precondition(buffer.frameLength == 2646)
            let data = buffer.floatChannelData![0]
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) {
                let expected = Float(Int16(bitPattern: UInt16(wav[44+2*i]) | UInt16(wav[45+2*i]) << 8)) / 32768
                precondition(data[i] == expected && data[i].isFinite)
                peak = max(peak, abs(data[i]))
            }
            precondition(peak > 0.1 && peak < 1)
            precondition(data[Int(buffer.frameLength)-1] == 0)
        }
        func sample(_ voice: ClickVoice, _ index: Int) -> Double {
            let buffer = try! BeatAudioEngine.makeBuffer(voice: voice)
            return Double(buffer.floatChannelData![0][index])
        }
        for (voice, frequency, gain) in [(ClickVoice.lowPitch, 220.0, 0.4),
                                         (.highPitch, 1760.0, 0.4), (.accented, 1144.0, 0.6)] {
            for i in [100, 173, 389, 1000] {
                let t = Double(i) / 44100
                let envelope = pow(1 - Double(i) / 2645, 2)
                let expected = sin(2 * Double.pi * frequency * t) * envelope * gain
                precondition(abs(sample(voice, i) - expected) < 0.0001)
            }
        }
        print("Audio buffers preserve every PCM sample, duration, format and envelope for all six voices")
    }
}
