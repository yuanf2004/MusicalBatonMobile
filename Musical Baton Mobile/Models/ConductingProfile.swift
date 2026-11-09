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
    // Legacy fields retained so existing saved profiles decode without migration.
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
