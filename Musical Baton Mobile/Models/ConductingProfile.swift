import Foundation

nonisolated enum ClickVoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case click, wood, bell
    var id: String { rawValue }
    var title: String {
        switch self { case .click: "Click"; case .wood: "Wood tap"; case .bell: "Bell" }
    }
}

nonisolated enum DetectionSensitivity: Int, Codable, CaseIterable, Identifiable, Sendable {
    case balanced = 0, deliberate = 1, gentle = 2
    var id: Int { rawValue }
    var title: String {
        switch self { case .balanced: "Balanced"; case .deliberate: "Deliberate strokes"; case .gentle: "Gentle strokes" }
    }
}

nonisolated struct ConductingProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = "My conducting profile"
    var beatsPerMeasure = 4
    var sensitivity: DetectionSensitivity = .balanced
    var downbeatSound: ClickVoice = .bell
    var otherBeatSound: ClickVoice = .click

    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 60 && (2...4).contains(beatsPerMeasure)
    }
}

nonisolated enum ConductingSettingsPacket {
    static let characteristicUUID = "12345678-1234-5678-1234-56789ABCDEF3"
    static func encode(_ sensitivity: DetectionSensitivity) -> Data {
        Data([1, 1, UInt8(sensitivity.rawValue), 0])
    }
}

// Tracks received beat events, not musical direction. Never invent a missing sound.
nonisolated struct MeasureCounter {
    private(set) var position = 0
    private var previousSequence: UInt16?
    private var previousTime: UInt32?

    mutating func reset() { self = MeasureCounter() }

    // A transport gap or >2 s pause loses phase. Require an explicit new downbeat.
    mutating func advance(_ packet: BatonBeatPacket, beatsPerMeasure: Int) -> Int? {
        guard (2...4).contains(beatsPerMeasure) else { return nil }
        if let previousSequence, let previousTime {
            guard packet.sequence &- previousSequence == 1,
                  packet.uptimeMilliseconds &- previousTime <= 2000 else { return nil }
        }
        previousSequence = packet.sequence
        previousTime = packet.uptimeMilliseconds
        position = position % beatsPerMeasure + 1
        return position
    }
}
