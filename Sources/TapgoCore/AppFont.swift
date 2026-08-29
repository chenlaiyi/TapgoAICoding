import SwiftUI

/// Global font scale selectable from Settings → Appearance.
///
/// Why a custom scale (instead of `dynamicTypeSize` or `scaleEffect`):
///   - `dynamicTypeSize` is honored inconsistently by SwiftUI on macOS —
///     some views resolve text styles against the environment, others
///     ignore it. We saw that empirically: chat bubble text scaled,
///     sidebar session titles did not.
///   - `scaleEffect` does scale the rendered output, but it also scales
///     layout (positions, padding, frames) which breaks alignment and
///     causes clipping. It must never be used at the root.
///   - Explicit `.system(size:)` resolved through this enum is the
///     only approach that is (a) visible everywhere, (b) doesn't break
///     layout, and (c) survives across view rebuilds.
public enum AppFontScale: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    /// User-facing Chinese label used by the Settings picker and the
    /// ChatView "字体大小" menu.
    public var displayName: String {
        switch self {
        case .small:  return "小"
        case .medium: return "中"
        case .large:  return "大"
        }
    }

    /// Multiplier applied to each base point size.
    ///   - small  → 0.85×  (~13% smaller, still readable)
    ///   - medium → 1.00×  (matches the pre-feature UI exactly)
    ///   - large  → 1.20×  (~20% larger, accessibility-friendly)
    public var multiplier: CGFloat {
        switch self {
        case .small:  return 0.85
        case .medium: return 1.00
        case .large:  return 1.20
        }
    }

    /// `UserDefaults` key. Same value used by `@AppStorage` in
    /// SettingsView + ChatView + App so all three read/write the same
    /// persisted preference.
    public static let userDefaultsKey = "tapgo.fontScale"

    /// Resolves the current persisted scale.
    public static func current() -> AppFontScale {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "medium"
        return AppFontScale(rawValue: raw) ?? .medium
    }
}

// MARK: - Environment

private struct AppFontScaleKey: EnvironmentKey {
    /// Defaults to `.medium` so views that are previewed in isolation
    /// (e.g. Xcode previews) render at the same size as production.
    static let defaultValue: AppFontScale = .medium
}

extension EnvironmentValues {
    /// Current global font scale. Set once at the App root via
    /// `.appFontScale(_:)`; read by any view that needs to resolve
    /// `AppFont.scaled(_:multiplier:)`.
    public var tapgoFontScale: AppFontScale {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

// MARK: - AppFont

/// Centralized font tokens. **Every** text style in the app should be
/// resolved through here so the user's Appearance → Font Size
/// preference scales the whole UI uniformly.
///
/// Base sizes match the macOS SwiftUI defaults for each text style so
/// picking "中" looks identical to the pre-feature UI. The `small` /
/// `large` levels are visibly different.
public enum AppFont {
    /// Base point sizes for each text style at the "中" level.
    /// Tweaking these changes the rendered size of every `.font(.xxx)`
    /// replacement in the codebase, so keep them centralized here.
    private static let baseSizes: [Font.TextStyle: CGFloat] = [
        .largeTitle:  26,
        .title:       22,
        .title2:      17,
        .title3:      15,
        .headline:    13,
        .body:        13,
        .callout:     12,
        .subheadline: 11,
        .footnote:    10,
        .caption:     11,
        .caption2:     9
    ]

    /// Returns a system font sized for the given text style using
    /// the supplied multiplier. Use this in place of `.font(.body)`
    /// etc. so every label honors the user's Appearance picker.
    public static func scaled(_ style: Font.TextStyle, multiplier: CGFloat) -> Font {
        let base = baseSizes[style] ?? 13
        return .system(size: base * multiplier)
    }

    /// 单点像素尺寸 helper（无字体绘制，纯数值），供 markdown 解析等需要
    /// 按文本样式 + multiplier 计算具体 point size 的场景使用。
    public static func pointSize(for style: Font.TextStyle, multiplier: CGFloat) -> CGFloat {
        (baseSizes[style] ?? 13) * multiplier
    }

    /// Monospaced variant for code / paths / timestamps. Caller picks
    /// the base size; this helper applies the supplied multiplier.
    public static func monoScaled(size: CGFloat, weight: Font.Weight = .regular, multiplier: CGFloat) -> Font {
        .system(size: size * multiplier, weight: weight, design: .monospaced)
    }
}

// MARK: - View modifier

extension View {
    /// Applies the global font scale to all descendants. Apply once
    /// at the App root so every view reading `\.appFontScale` sees the
    /// same value the user picked in Settings → Appearance.
    public func appFontScale(_ scale: AppFontScale) -> some View {
        environment(\.tapgoFontScale, scale)
    }
}
