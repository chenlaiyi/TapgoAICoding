// TomlKey — 把 provider id 渲染成合法的 TOML 键（v0.5.319 修）。
//
// codex `config.toml` 的 provider 段名形如 `[model_providers.<key>]`，其中
// `<key>` 是**裸键**：TOML 只允许 `A-Za-z0-9_-`。老注册表里遗留的
// `builtin:zhipu` / `builtin:minimax` 之类 id 含 `:`，直接拼进段名会让
// 整份 config.toml 解析失败（codex 报 `invalid unquoted key`），
// codex app-server 连 `initialize` 都跑不起来 —— App 侧表现为会话直接失败。
//
// 这里统一转义：非裸键安全时加双引号。TOML 引号键的**字符串值**仍是原 id，
// 所以顶层 `model_provider = "<id>"` 与 thread/start 的 runtime override
// 引用不受影响。

import Foundation

public enum TomlKey {
    /// 是否可以直接作为 TOML 裸键（仅 A-Z a-z 0-9 _ -）。
    public static func isBareSafe(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return key.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F:
                return true
            default:
                return false
            }
        }
    }

    /// `[model_providers.<这里>]` 的键文本：安全则裸键，否则双引号包裹。
    public static func providerSectionKey(_ id: String) -> String {
        isBareSafe(id) ? id : "\"\(basicStringEscaped(id))\""
    }

    /// TOML basic string 内容转义（反斜杠、双引号、控制字符）。
    public static func basicStringEscaped(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C: out += "\\\\"
            case 0x22: out += "\\\""
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1F, 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
