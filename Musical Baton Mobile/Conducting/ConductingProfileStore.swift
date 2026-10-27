import Foundation
import Observation

@MainActor
@Observable
final class ConductingProfileStore {
    private(set) var profiles: [ConductingProfile] = []
    private(set) var selectedID: UUID?
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "conducting.profiles.v1"

    private struct Archive: Codable {
        var version = 1
        var profiles: [ConductingProfile]
        var selectedID: UUID?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                let archive = try JSONDecoder().decode(Archive.self, from: data)
                guard archive.version == 1, archive.profiles.allSatisfy(\.isValid),
                      Set(archive.profiles.map(\.id)).count == archive.profiles.count else {
                    throw StoreError.invalid
                }
                profiles = archive.profiles
                selectedID = profiles.contains(where: { $0.id == archive.selectedID }) ? archive.selectedID : profiles.first?.id
            } catch {
                self.error = "Saved profiles could not be loaded. Create a new profile to replace the invalid saved data."
            }
        } else {
            let starter = ConductingProfile(name: "Four-beat practice")
            profiles = [starter]
            selectedID = starter.id
            persist()
        }
    }

    var selected: ConductingProfile? { profiles.first { $0.id == selectedID } }

    @discardableResult
    func save(_ draft: ConductingProfile) -> Bool {
        var profile = draft
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.isValid else { error = "Use a name of 1–60 characters and 2–4 beats per measure."; return false }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        selectedID = profile.id
        return persist()
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if selectedID == id { selectedID = profiles.first?.id }
        persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(Archive(profiles: profiles, selectedID: selectedID))
            defaults.set(data, forKey: Self.key)
            error = nil
            return true
        } catch { self.error = "Could not save profiles: \(error.localizedDescription)"; return false }
    }

    private enum StoreError: Error { case invalid }
}
