import Foundation

/// One reasoning level the Host's adapter offers for a model route.
struct MobileModelReasoning: Identifiable, Equatable {
    let id: String
    let name: String
}

/// One model offered by the paired Host, including its selectable reasoning levels.
struct MobileModel: Identifiable, Equatable {
    let id: String
    let provider: String
    let model: String
    let name: String
    let detail: String?
    let efforts: [MobileModelReasoning]
    let defaultEffort: String?

    /// Joins one provider route with the Host's display and reasoning metadata.
    /// - Parameters:
    ///   - provider: provider id owning the route.
    ///   - model: adapter model id.
    ///   - name: display name reported by the Host.
    ///   - detail: optional provider description.
    ///   - efforts: selectable reasoning levels; empty when the route has none.
    ///   - defaultEffort: level the Host applies when a selection omits one.
    init(provider: String, model: String, name: String, detail: String? = nil,
         efforts: [MobileModelReasoning] = [], defaultEffort: String? = nil) {
        self.id = "\(provider)/\(model)"
        self.provider = provider
        self.model = model
        self.name = name
        self.detail = detail
        self.efforts = efforts
        self.defaultEffort = defaultEffort
    }
}

/// Reads the Host model catalog and decides whether a choice still needs a Host request.
enum MobileModelCatalog {
    /// Parses `session/modelCatalog` groups into flat provider routes.
    /// - Parameter catalog: raw `session/modelCatalog` value.
    /// - Returns: every model the Host currently offers, in group order.
    static func models(from catalog: [String: Any]) -> [MobileModel] {
        (catalog["groups"] as? [[String: Any]] ?? []).flatMap { group -> [MobileModel] in
            guard let provider = group["id"] as? String else { return [] }
            return (group["models"] as? [[String: Any]] ?? []).compactMap { item in
                guard let model = item["id"] as? String else { return nil }
                let reasoning = item["reasoning"] as? [String: Any]
                let efforts = (reasoning?["efforts"] as? [[String: Any]] ?? []).compactMap { effort -> MobileModelReasoning? in
                    guard let id = effort["id"] as? String, !id.isEmpty else { return nil }
                    return MobileModelReasoning(id: id, name: effort["name"] as? String ?? id)
                }
                return MobileModel(provider: provider, model: model, name: item["name"] as? String ?? model,
                                   detail: item["description"] as? String, efforts: efforts,
                                   defaultEffort: reasoning?["defaultEffort"] as? String)
            }
        }
    }

    /// Reads the route the Host uses for Sessions that have no selection yet.
    /// - Parameter catalog: raw `session/modelCatalog` value.
    /// - Returns: `provider/model`, or nil when the catalog omits the default.
    static func defaultRoute(from catalog: [String: Any]) -> String? {
        guard let fallback = catalog["default"] as? [String: Any],
              let provider = fallback["provider"] as? String,
              let model = fallback["model"] as? String else { return nil }
        return "\(provider)/\(model)"
    }

    /// Whether choosing `model` and `effort` still changes the Host's selection.
    /// - Parameters:
    ///   - currentModel: route currently reported by the Host, if any.
    ///   - currentEffort: reasoning level currently reported by the Host, if any.
    ///   - model: route the user chose.
    ///   - effort: reasoning level the user chose; nil keeps the model's default.
    /// - Returns: `true` when a `session/selectModel` request is still required.
    static func requiresSelection(currentModel: String?, currentEffort: String?,
                                  model: MobileModel, effort: String?) -> Bool {
        guard currentModel == model.id else { return true }
        guard !model.efforts.isEmpty else { return false }
        return (currentEffort ?? model.defaultEffort) != (effort ?? model.defaultEffort)
    }

    /// Names one reasoning level the way the Host labels it.
    /// - Parameters:
    ///   - effort: effort id to resolve.
    ///   - model: route that declares the level.
    /// - Returns: the Host's label, or nil when the route does not offer that level.
    static func effortName(_ effort: String?, in model: MobileModel?) -> String? {
        guard let effort, let model,
              let declared = model.efforts.first(where: { $0.id == effort }) else { return nil }
        return declared.name
    }
}
