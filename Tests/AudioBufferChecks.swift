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
        print("Audio buffers preserve every PCM sample, duration, format and envelope for all three voices")
    }
}
