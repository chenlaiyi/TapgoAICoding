import Foundation
import SwiftUI

/// v0.5.199: 把带 ANSI escape sequence 的字符串拆成 (text, fg color, bold) 流，
/// 供 SwiftUI Text/AttributedString 渲染用。支持 SGR（ESC[<n>m）颜色码：
/// - 8-color (30-37 / 90-97)
/// - 256-color (38;5;N)
/// - truecolor (38;2;R;G;B)
/// - reset (0) / bold (1) / unbold (22)
public enum ANSIParser {
    public struct Segment: Equatable {
        public let text: String
        public let fg: ANSIColor?
        public let bold: Bool
        public init(text: String, fg: ANSIColor? = nil, bold: Bool = false) {
            self.text = text
            self.fg = fg
            self.bold = bold
        }
    }
    public struct Line: Equatable {
        public let segments: [Segment]
    }
    /// 解析整个字符串（含换行）为多行 segments。
    public static func parse(_ raw: String) -> [Line] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map { parseLine(String($0)) }
    }
    /// 解析单行（不含换行）。
    public static func parseLine(_ raw: String) -> Line {
        var segments: [Segment] = []
        var currentText = ""
        var currentFg: ANSIColor? = nil
        var currentBold = false
        var i = raw.startIndex
        while i < raw.endIndex {
            let c = raw[i]
            // ESC [
            if c == "\u{1B}",
               let next = raw.index(i, offsetBy: 1, limitedBy: raw.endIndex),
               next < raw.endIndex, raw[next] == "[" {
                if !currentText.isEmpty {
                    segments.append(Segment(text: currentText, fg: currentFg, bold: currentBold))
                    currentText = ""
                }
                var j = raw.index(after: next)
                var foundTerm = false
                while j < raw.endIndex {
                    let cc = raw[j]
                    if cc == "m" {
                        let paramsStr = String(raw[raw.index(after: next)..<j])
                        apply(params: paramsStr, fg: &currentFg, bold: &currentBold)
                        i = raw.index(after: j)
                        foundTerm = true
                        break
                    }
                    j = raw.index(after: j)
                }
                if !foundTerm { i = raw.endIndex }
            } else {
                currentText.append(c)
                i = raw.index(after: i)
            }
        }
        if !currentText.isEmpty {
            segments.append(Segment(text: currentText, fg: currentFg, bold: currentBold))
        }
        return Line(segments: segments)
    }
    private static func apply(params paramsStr: String, fg: inout ANSIColor?, bold: inout Bool) {
        let params = paramsStr.isEmpty ? [0] : paramsStr.split(separator: ";").compactMap { Int($0) }
        var idx = 0
        while idx < params.count {
            let p = params[idx]
            switch p {
            case 0: fg = nil; bold = false
            case 1: bold = true
            case 22: bold = false
            case 30...37: fg = .palette(p - 30)
            case 90...97: fg = .palette(p - 90 + 8)
            case 39: fg = nil
            case 38:
                if idx + 1 < params.count {
                    let mode = params[idx + 1]
                    if mode == 5, idx + 2 < params.count {
                        let n = params[idx + 2]
                        fg = .palette(n)
                        idx += 2
                    } else if mode == 2, idx + 4 < params.count {
                        let r = UInt8(clamping: params[idx + 2])
                        let g = UInt8(clamping: params[idx + 3])
                        let b = UInt8(clamping: params[idx + 4])
                        fg = .rgb(r, g, b)
                        idx += 4
                    } else {
                        fg = nil
                    }
                }
            default: break
            }
            idx += 1
        }
    }
}

public enum ANSIColor: Equatable {
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
    /// 映射到 SwiftUI Color（16-color palette 用近似 ANSI 终端色）。
    public static func swiftUIColor(_ color: ANSIColor, fallback: Color = .primary) -> Color {
        switch color {
        case .palette(let i):
            let palette: [Color] = [
                Color(red: 0.10, green: 0.10, blue: 0.10),
                Color(red: 0.85, green: 0.30, blue: 0.30),
                Color(red: 0.40, green: 0.85, blue: 0.40),
                Color(red: 0.90, green: 0.78, blue: 0.30),
                Color(red: 0.45, green: 0.60, blue: 0.95),
                Color(red: 0.85, green: 0.50, blue: 0.85),
                Color(red: 0.40, green: 0.85, blue: 0.85),
                Color(red: 0.85, green: 0.85, blue: 0.85),
                Color(red: 0.45, green: 0.45, blue: 0.45),
                Color(red: 1.00, green: 0.45, blue: 0.45),
                Color(red: 0.55, green: 1.00, blue: 0.55),
                Color(red: 1.00, green: 0.95, blue: 0.55),
                Color(red: 0.60, green: 0.75, blue: 1.00),
                Color(red: 1.00, green: 0.65, blue: 1.00),
                Color(red: 0.55, green: 1.00, blue: 1.00),
                Color(red: 1.00, green: 1.00, blue: 1.00),
            ]
            let idx = max(0, min(palette.count - 1, i))
            return palette[idx]
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        }
    }
}
