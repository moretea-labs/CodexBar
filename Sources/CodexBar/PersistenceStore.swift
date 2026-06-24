import Foundation

enum PersistenceStore {
    private static let key = "CodexBar.preferences.v1"

    static func load() -> PersistedPreferences? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedPreferences.self, from: data)
    }

    static func save(_ preferences: PersistedPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
