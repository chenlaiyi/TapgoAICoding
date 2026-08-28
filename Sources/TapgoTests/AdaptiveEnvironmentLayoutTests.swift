import Foundation
@testable import TapgoCore

@MainActor
func runAdaptiveEnvironmentLayoutTests(_ t: TestRunner) {
    let standardWidth = AdaptiveEnvironmentLayout.minimumWindowWidth(preferredChatWidth: 720)
    t.expectEqual(standardWidth, 1_428, "standard threshold includes sidebar, chat, card and spacing")
    t.expect(
        !AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: standardWidth - 1,
            preferredChatWidth: 720,
            hasActiveThread: true,
            manualDetailVisible: false
        ),
        "one point below threshold hides the card"
    )
    t.expect(
        AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: standardWidth,
            preferredChatWidth: 720,
            hasActiveThread: true,
            manualDetailVisible: false
        ),
        "threshold shows the card"
    )

    let wideWidth = AdaptiveEnvironmentLayout.minimumWindowWidth(preferredChatWidth: 980)
    t.expectEqual(wideWidth, 1_688, "wide chat preference raises the threshold")
    t.expect(
        !AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: standardWidth,
            preferredChatWidth: 980,
            hasActiveThread: true,
            manualDetailVisible: false
        ),
        "wide chat does not sacrifice its content width for the card"
    )
    t.expect(
        !AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: 2_000,
            preferredChatWidth: 720,
            hasActiveThread: false,
            manualDetailVisible: false
        ),
        "no active thread hides the card"
    )
    t.expect(
        !AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: 2_000,
            preferredChatWidth: 720,
            hasActiveThread: true,
            manualDetailVisible: true
        ),
        "manual trajectory detail takes precedence"
    )
}
