import Foundation

/// Responsive visibility policy for the floating environment/source card.
///
/// The calculation deliberately uses the full window width rather than the
/// chat column width. `ContentView` owns the project sidebar and therefore is
/// the only layer that can decide whether the preferred chat width, sidebar,
/// card and breathing room all fit without covering the conversation.
public enum AdaptiveEnvironmentLayout {
    public static let projectSidebarWidth: Double = 280
    public static let cardWidth: Double = 328
    public static let layoutSpacing: Double = 100

    public static func minimumWindowWidth(preferredChatWidth: Double) -> Double {
        projectSidebarWidth + preferredChatWidth + cardWidth + layoutSpacing
    }

    public static func shouldShow(
        windowWidth: Double,
        preferredChatWidth: Double,
        hasActiveThread: Bool,
        manualDetailVisible: Bool
    ) -> Bool {
        guard hasActiveThread, !manualDetailVisible else { return false }
        return windowWidth >= minimumWindowWidth(preferredChatWidth: preferredChatWidth)
    }
}
