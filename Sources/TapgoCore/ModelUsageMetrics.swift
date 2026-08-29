import Foundation

/// 计算弹窗里"平均缓存命中率 / 上下文占比"等纯数据指标的工具集合,
/// 与 SwiftUI 解耦,可在单元测试里直接验证。
public enum ModelUsageMetrics {
    /// 把多个 `Turn.usage.cached / .input` 平均成整数百分比;
    /// 无数据 / input 全为 0 时返回 nil。
    public static func averageCacheHitPercent(turns: [Turn]) -> Int? {
        let ratios: [Double] = turns.compactMap { t in
            guard let u = t.usage, u.input > 0 else { return nil }
            return Double(u.cached) / Double(u.input)
        }
        guard !ratios.isEmpty else { return nil }
        return Int((ratios.reduce(0, +) / Double(ratios.count) * 100).rounded())
    }

    /// `value / window` 的整数百分比;`window <= 0` 时返回 0。
    public static func percentOfWindow(_ value: Int, window: Int) -> Int {
        guard window > 0 else { return 0 }
        return Int((Double(value) / Double(window) * 100).rounded())
    }
}
