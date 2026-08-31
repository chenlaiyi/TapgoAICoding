import Foundation

/// The persistent, UI-independent state for the ZCode-style trailing
/// workbench. Keeping the lifecycle rules in TapgoCore makes tab restoration
/// deterministic and directly testable without launching SwiftUI.
public struct WorkbenchLayoutState: Codable, Equatable {
    public enum TabKind: String, Codable, CaseIterable, Sendable {
        case assistant
        case review
        case terminal
        case browser

        public var defaultTitle: String {
            switch self {
            case .assistant: return "辅助对话"
            case .review: return "审查"
            case .terminal: return "default"
            case .browser: return "浏览器"
            }
        }

        /// Review and browser are workspace-level surfaces. Opening either
        /// again selects the existing tab. Assistant and terminal tabs are
        /// sessions and may coexist in multiple instances.
        public var allowsMultipleInstances: Bool {
            self == .assistant || self == .terminal
        }
    }

    public struct Tab: Identifiable, Codable, Equatable, Sendable {
        public var id: String
        public var kind: TabKind
        public var title: String
        /// Local Tapgo thread id owned by an auxiliary-conversation tab.
        /// Optional keeps layouts written by v0.5.61 previews decodable.
        public var linkedThreadID: String?

        public init(id: String, kind: TabKind, title: String, linkedThreadID: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.linkedThreadID = linkedThreadID
        }
    }

    public var tabs: [Tab]
    public var selectedTabID: String?
    public var isEnvironmentVisible: Bool

    public init(
        tabs: [Tab] = [Tab(id: "review", kind: .review, title: "审查")],
        selectedTabID: String? = "review",
        isEnvironmentVisible: Bool = false
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.isEnvironmentVisible = isEnvironmentVisible
        sanitize()
    }

    public static var `default`: WorkbenchLayoutState { WorkbenchLayoutState() }

    @discardableResult
    public mutating func open(_ kind: TabKind) -> String {
        if !kind.allowsMultipleInstances,
           let existing = tabs.first(where: { $0.kind == kind }) {
            selectedTabID = existing.id
            return existing.id
        }

        let ordinal = tabs.filter { $0.kind == kind }.count + 1
        let title: String
        switch kind {
        case .assistant:
            title = "辅助对话 \(ordinal)"
        case .terminal:
            title = ordinal == 1 ? "default" : "default \(ordinal)"
        default:
            title = kind.defaultTitle
        }
        let id = kind.allowsMultipleInstances
            ? "\(kind.rawValue)-\(UUID().uuidString.lowercased())"
            : kind.rawValue
        tabs.append(Tab(id: id, kind: kind, title: title))
        selectedTabID = id
        return id
    }

    public mutating func linkThread(_ threadID: String, toTab id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              tabs[index].kind == .assistant else { return }
        tabs[index].linkedThreadID = threadID
    }

    public mutating func select(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    public mutating func close(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        tabs.remove(at: index)
        guard wasSelected else { return }
        guard !tabs.isEmpty else {
            selectedTabID = nil
            return
        }
        selectedTabID = tabs[min(index, tabs.count - 1)].id
    }

    public mutating func closeOthers(keeping id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tabs = [tab]
        selectedTabID = id
    }

    public mutating func ensureUsableSelection() {
        sanitize()
        if tabs.isEmpty {
            _ = open(.review)
        }
    }

    private mutating func sanitize() {
        var singletonKinds = Set<TabKind>()
        tabs = tabs.filter { tab in
            guard !tab.id.isEmpty, !tab.title.isEmpty else { return false }
            guard !tab.kind.allowsMultipleInstances else { return true }
            return singletonKinds.insert(tab.kind).inserted
        }
        if let selectedTabID,
           !tabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = tabs.first?.id
        } else if selectedTabID == nil {
            selectedTabID = tabs.first?.id
        }
    }
}
