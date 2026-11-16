import Foundation

/// Remembers the model route and reasoning level this iPhone used with each paired Host.
enum MobileModelPreference {
    static func read(computerID: String) -> String? {
        UserDefaults.standard.string(forKey: "dsh.mobile.last-model.\(computerID)")
    }

    /// Reads the reasoning level this iPhone last used with a paired Host.
    /// - Parameter computerID: paired Host identity.
    /// - Returns: the effort id, or nil when the last confirmed selection had none.
    static func readEffort(computerID: String) -> String? {
        UserDefaults.standard.string(forKey: "dsh.mobile.last-effort.\(computerID)")
    }

    /// Stores the model route this iPhone used with a paired Host.
    /// - Parameters:
    ///   - modelID: `provider/model` route.
    ///   - effort: reasoning level confirmed with it; nil clears a stored level.
    ///   - computerID: paired Host identity.
    static func save(_ modelID: String, effort: String? = nil, computerID: String) {
        UserDefaults.standard.set(modelID, forKey: "dsh.mobile.last-model.\(computerID)")
        let key = "dsh.mobile.last-effort.\(computerID)"
        if let effort { UserDefaults.standard.set(effort, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
