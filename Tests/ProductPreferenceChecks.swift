import Foundation

@main
struct ProductPreferenceChecks {
    @MainActor static func main() {
        let name = "BatonProductChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = ProductPreferences(defaults: defaults)
        precondition(prefs.scanSeconds == 30 && prefs.connectionSeconds == 0)
        prefs.scanSeconds = 120
        prefs.connectionSeconds = 300
        let id = UUID()
        precondition(prefs.rename(id: id, name: "  Concert baton  "))
        let reload = ProductPreferences(defaults: defaults)
        precondition(reload.scanSeconds == 120 && reload.connectionSeconds == 300)
        precondition(reload.name(id: id, fallback: "Radio") == "Concert baton")
        precondition(reload.name(id: UUID(), fallback: "Other") == "Other")
        precondition(!reload.rename(id: id, name: String(repeating: "x", count: 41)))
        precondition(reload.name(id: id, fallback: "Radio") == "Concert baton")
        precondition(reload.rename(id: id, name: " \n "))
        precondition(ProductPreferences(defaults: defaults).name(id: id, fallback: "Radio") == "Radio")
        defaults.set(-1, forKey: "product.scanSeconds")
        defaults.set(47, forKey: "product.connectionSeconds")
        precondition(ProductPreferences(defaults: defaults).scanSeconds == 30)
        precondition(ProductPreferences(defaults: defaults).connectionSeconds == 0)
        precondition(!ConnectionTimePolicy.expired(start: nil, now: 100, limit: 30))
        precondition(!ConnectionTimePolicy.expired(start: 10, now: 39.999, limit: 30))
        precondition(ConnectionTimePolicy.expired(start: 10, now: 40, limit: 30))
        precondition(ConnectionTimePolicy.expired(start: 10, now: 900, limit: 30)) // Resume after suspension.
        precondition(!ConnectionTimePolicy.expired(start: 10, now: 99999, limit: 0))
        precondition(ConnectionTimePolicy.expired(start: 10, now: 45, limit: 30)) // Shortened active limit.
        precondition(!ConnectionTimePolicy.expired(start: 10, now: 45, limit: 60)) // Extended active limit.
        print("Product scan/TTL boundaries, suspension elapsed time, persistence, invalid defaults and per-device nicknames passed")
    }
}
