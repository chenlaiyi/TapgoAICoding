import Foundation
import CoreGraphics

/// AppKit coordinates (bottom-left origin), including displays left of or above
/// the primary display. Keep the guide on the display containing its target.
public enum PermissionGuideLayout {
    public static func frame(
        below settings: CGRect,
        visibleScreens: [CGRect],
        preferredSize: CGSize = CGSize(width: 590, height: 142)
    ) -> CGRect? {
        let candidates = visibleScreens.filter { $0.width > 24 && $0.height > 24 }
        guard settings.width > 0, settings.height > 0,
              let screen = candidates.max(by: { overlap(settings, $0) < overlap(settings, $1) }),
              overlap(settings, screen) > 0 else { return nil }
        let margin: CGFloat = 12
        let size = CGSize(width: min(preferredSize.width, screen.width - 2 * margin),
                          height: min(preferredSize.height, screen.height - 2 * margin))
        let x = min(max(settings.midX - size.width / 2, screen.minX + margin), screen.maxX - size.width - margin)
        let y = min(max(settings.minY - size.height - margin, screen.minY + margin), screen.maxY - size.height - margin)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
