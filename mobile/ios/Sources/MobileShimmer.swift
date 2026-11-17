import SwiftUI

/// A moving highlight for text that is actively changing, without changing its layout.
private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 0.06)) { context in
                    GeometryReader { geometry in
                        let width = max(40, geometry.size.width)
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, Color.white.opacity(0.95), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.5)
                            .offset(x: -width * 0.5 + (width * 1.5) * phase)
                            .mask(content)
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
