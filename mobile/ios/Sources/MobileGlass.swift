import SwiftUI

/// Shared floating-control material, with an opaque surface when reduced transparency is enabled.
private struct MobileGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface
    let interactive: Bool

    private var usesOpaqueSurface: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-reduce-transparency") { return true }
        #endif
        return reduceTransparency
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesOpaqueSurface {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        }
    }
}

extension View {
    /// Applies the app's floating-control material to the complete padded control.
    func mobileGlass<Surface: Shape>(in shape: Surface, interactive: Bool = false) -> some View {
        modifier(MobileGlassSurface(shape: shape, interactive: interactive))
    }
}
