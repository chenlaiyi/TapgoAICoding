import Foundation

/// Remembers which project folders a reader folded, per paired computer.
enum MobileProjectCollapseStore {
    /// Storage key for one computer's folded projects.
    /// - Parameter computerID: stable paired-computer identity.
    /// - Returns: the defaults key.
    static func key(computerID: String) -> String {
        "mobile.collapsedProjects.\(computerID)"
    }

    /// Reads the stored folded project paths.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: workspace paths currently folded.
    static func load(computerID: String, defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: key(computerID: computerID)),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    /// Stores the folded project paths, or clears the key when nothing is folded.
    /// - Parameters:
    ///   - projects: workspace paths currently folded.
    ///   - computerID: stable paired-computer identity.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func save(_ projects: Set<String>, computerID: String, defaults: UserDefaults = .standard) {
        guard !projects.isEmpty, let data = try? JSONEncoder().encode(projects.sorted()) else {
            defaults.removeObject(forKey: key(computerID: computerID))
            return
        }
        defaults.set(data, forKey: key(computerID: computerID))
    }

    /// Removes one computer's folded projects.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func clear(computerID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(computerID: computerID))
    }
}
