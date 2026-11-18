import SwiftUI

/// A moving highlight for text that is actively changing, without changing its layout.
private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The sweep lifts the secondary row text to primary inside the band; the dark appearance needs
    /// more of the lift to stay visible on a dark background.
    private var tint: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.6 : 0.9)
    }

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                GeometryReader { geometry in
                    TimelineView(.animation) { context in
                        let width = max(geometry.size.width, 1)
                        let cycle: TimeInterval = 1.5
                        let sweep: TimeInterval = 1
                        let elapsed = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle)
                        let progress = min(elapsed / sweep, 1)
                        tint
                            .mask(content)
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white, location: 0.42),
                                    .init(color: .white, location: 0.58),
                                    .init(color: .clear, location: 1),
                                ], startPoint: .leading, endPoint: .trailing)
                                .frame(width: width)
                                .offset(x: width * (progress * 2 - 1))
                            }
                    }
                }
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Shimmers text while a run is updating in place.
    /// - Parameter active: whether the row is live.
    /// - Returns: the view, with a moving highlight when active.
    func mobileShimmering(_ active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}
