import Foundation
import TapgoCore

// MARK: - v0.5.319 TomlKey 回归
//
// 供应商精简后，老注册表里遗留的 `builtin:zhipu` / `builtin:minimax` 会被
// 当成「自定义 Provider」。如果直接把这类 id 拼进 `[model_providers.<id>]`
// 段名，含 `:` 的裸键不是合法 TOML，codex 会拒绝加载**整份** config.toml
// （`invalid unquoted key, expected letters, numbers, -, _`），
// codex app-server 连 initialize 都起不来 —— 用户侧表现为会话直接失败。
// 这里锁住「非裸键安全 → 加双引号」的渲染契约。
func runTomlKeyProviderSectionTests(_ t: TestRunner) {
    t.section("TomlKey: provider 段名转义")

    t.expect(TomlKey.isBareSafe("deepseek"), "deepseek 是合法裸键")
    t.expect(TomlKey.isBareSafe("custom-1A2B3C4D"), "custom-<id8> 是合法裸键")
    t.expect(TomlKey.isBareSafe("a_b-9"), "字母/数字/下划线/连字符是合法裸键")
    t.expect(!TomlKey.isBareSafe("builtin:zhipu"), "含冒号的遗留 id 不是合法裸键")
    t.expect(!TomlKey.isBareSafe(""), "空 id 不是合法裸键")
    t.expect(!TomlKey.isBareSafe("智谱"), "非 ASCII 不是合法裸键")
    t.expect(!TomlKey.isBareSafe("a b"), "含空格不是合法裸键")

    t.expectEqual(TomlKey.providerSectionKey("deepseek"), "deepseek",
                  "内置 deepseek 段名保持不变（不引入多余引号）")
    t.expectEqual(TomlKey.providerSectionKey("custom-1A2B3C4D"), "custom-1A2B3C4D",
                  "自定义 provider 段名保持不变")
    t.expectEqual(TomlKey.providerSectionKey("builtin:zhipu"), "\"builtin:zhipu\"",
                  "遗留 builtin:<kind> 段名整体加双引号")

    let renderedLegacy = "model_providers.\(TomlKey.providerSectionKey("builtin:zhipu"))"
    t.expectEqual(renderedLegacy, "model_providers.\"builtin:zhipu\"",
                  "渲染结果与 codex 期望一致")
    t.expect(renderedLegacy.contains("\"builtin:zhipu\""),
             "段名里不允许出现未加引号的冒号（实际 \(renderedLegacy)）")

    t.expectEqual(TomlKey.basicStringEscaped("a\"b\\c"), "a\\\"b\\\\c",
                  "basic string 转义反斜杠与双引号")
    t.expectEqual(TomlKey.basicStringEscaped("line\nbreak"), "line\\nbreak",
                  "basic string 转义换行")
}
