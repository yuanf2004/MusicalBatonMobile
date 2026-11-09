import Foundation
import Observation

nonisolated enum ConnectionTimePolicy {
    static let scanChoices = [10, 30, 60, 120]
    static let connectionChoices = [0, 300, 900, 1800, 3600]

    static func expired(start: TimeInterval?, now: TimeInterval, limit: Int) -> Bool {
        guard let start, limit > 0 else { return false }
        return now - start >= Double(limit)
    }

    static func title(seconds: Int) -> String {
        if seconds == 0 { return "No limit" }
        return seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) minutes"
    }
}

@MainActor
@Observable
final class ProductPreferences {
    var scanSeconds: Int { didSet { defaults.set(scanSeconds, forKey: "product.scanSeconds") } }
    var connectionSeconds: Int { didSet { defaults.set(connectionSeconds, forKey: "product.connectionSeconds") } }
    private(set) var nicknames: [String: String]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let scan = defaults.integer(forKey: "product.scanSeconds")
        scanSeconds = ConnectionTimePolicy.scanChoices.contains(scan) ? scan : 30
        let ttl = defaults.integer(forKey: "product.connectionSeconds")
        connectionSeconds = ConnectionTimePolicy.connectionChoices.contains(ttl) ? ttl : 0
        nicknames = (defaults.dictionary(forKey: "product.nicknames") as? [String: String]) ?? [:]
    }

    func name(id: UUID, fallback: String) -> String { nicknames[id.uuidString] ?? fallback }

    @discardableResult
    func rename(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40 else { return false }
        nicknames[id.uuidString] = trimmed.isEmpty ? nil : trimmed
        defaults.set(nicknames, forKey: "product.nicknames")
        return true
    }
}
