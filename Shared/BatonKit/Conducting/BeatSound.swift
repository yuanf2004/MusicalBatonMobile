import Foundation

// Short, softly enveloped click/tap/bell voices. Generated in memory; no assets,
// network access, microphone permission, or file I/O on the beat path.
nonisolated enum BeatSound {
    static func wavData(voice: ClickVoice = .click, accented: Bool = false) -> Data {
        let rate = 44_100
        let count = rate * 60 / 1000
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32) {
            u16(UInt16(truncatingIfNeeded: value))
            u16(UInt16(truncatingIfNeeded: value >> 16))
        }
        text("RIFF"); u32(UInt32(36 + count * 2)); text("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2))
        u16(2); u16(16); text("data"); u32(UInt32(count * 2))
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let attack = min(1, t / 0.002)
            let release = max(0, 1 - Double(i) / Double(count - 1))
            let pitch = accented ? 1.3 : 1.0
            let wave: Double
            switch voice {
            case .click: wave = sin(2 * Double.pi * 880 * pitch * t)
            case .wood: wave = 0.7 * sin(2 * Double.pi * 420 * pitch * t)
                + 0.3 * sin(2 * Double.pi * 960 * pitch * t)
            case .bell: wave = 0.65 * sin(2 * Double.pi * 1320 * pitch * t)
                + 0.35 * sin(2 * Double.pi * 2112 * pitch * t)
            }
            let value = wave * attack * release * release * (accented ? 0.6 : 0.4)
            u16(UInt16(bitPattern: Int16(value * 32767)))
        }
        return data
    }
}
