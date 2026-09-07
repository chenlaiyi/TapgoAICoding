import Foundation
import TapgoCore

func runPluginCatalogCodexParsing(_ runner: TestRunner) {
    let json = #"""
    {
      "installed": [{
        "pluginId": "pdf@openai-primary-runtime",
        "name": "pdf",
        "marketplaceName": "openai-primary-runtime",
        "version": "1.2.3",
        "installed": true,
        "enabled": false,
        "source": {"path": "/tmp/pdf"}
      }],
      "available": [{
        "pluginId": "figma@openai-api-curated",
        "name": "figma",
        "marketplaceName": "openai-api-curated",
        "version": "2.0.0",
        "installed": false,
        "enabled": false,
        "source": {"path": "/tmp/figma"}
      }, {
        "pluginId": "git-skill@openai-api-curated",
        "name": "git-skill",
        "marketplaceName": "openai-api-curated",
        "version": null,
        "installed": false,
        "enabled": false,
        "source": {"source": "git", "url": "https://example.invalid/skill.git"}
      }]
    }
    """#.data(using: .utf8)!

    do {
        let items = try PluginCatalogParser.decodeCodex(json)
        runner.expectEqual(items.count, 3, "installed and available plugins are merged")
        runner.expectEqual(items.first?.name, "pdf", "installed plugins sort first")
        runner.expectEqual(items.first?.enabled, false, "disabled state is retained")
        runner.expect(items.contains { $0.matches("FIGMA") }, "search is case-insensitive")
        runner.expectEqual(items.first { $0.name == "git-skill" }?.version, "—",
                           "versionless git plugins remain visible")
    } catch {
        runner.expect(false, "Codex catalog decodes: \(error)")
    }
}

func runPluginCatalogConfigEditing(_ runner: TestRunner) {
    let base = "model = \"MiniMax-M3\"\n"
    let enabled = PluginConfigEditor.settingEnabled(true, for: "figma@openai-api-curated", in: base)
    runner.expect(enabled?.contains("[plugins.\"figma@openai-api-curated\"]") == true,
                  "missing plugin section is appended")
    runner.expect(enabled?.contains("enabled = true") == true, "enabled value is appended")

    let disabled = PluginConfigEditor.settingEnabled(false, for: "figma@openai-api-curated", in: enabled ?? "")
    runner.expect(disabled?.contains("enabled = false") == true, "existing enabled value is replaced")
    runner.expectEqual(disabled?.components(separatedBy: "[plugins.\"figma@openai-api-curated\"]").count, 2,
                       "toggle does not duplicate the plugin section")
    runner.expectNil(
        PluginConfigEditor.settingEnabled(true, for: "bad\"]\nmodel=\"evil", in: base),
        "unsafe plugin identifiers are rejected"
    )
}

func runPluginCatalogDeepSeekFiltering(_ runner: TestRunner) {
    let records = [
        NPMPackageSearchRecord(
            name: "@deepseek-ai/dsh-subagent-codex",
            version: "0.1.1-rc.2",
            description: "Codex subagent bundle"
        ),
        NPMPackageSearchRecord(
            name: "@deepseek-ai/dsh-subagent-acp",
            version: "0.1.1-rc.2",
            description: "Internal patch layer"
        ),
        NPMPackageSearchRecord(
            name: "@deepseek-ai/dsh-subagent-claude-code",
            version: "0.1.1-rc.2",
            description: "Claude Code subagent bundle"
        )
    ]
    let items = PluginCatalogParser.deepSeekItems(
        records,
        installedNames: ["@deepseek-ai/dsh-subagent-codex"]
    )

    runner.expectEqual(items.count, 2, "only documented official bundles are listed")
    runner.expect(items.allSatisfy { $0.installSpecifier.hasSuffix("@next") },
                  "DeepSeek installs use the release channel matching Harness")
    runner.expect(items.contains { $0.name == "@deepseek-ai/dsh-subagent-acp" } == false,
                  "internal DeepSeek patch packages stay hidden")
    runner.expect(items.first { $0.name == "@deepseek-ai/dsh-subagent-codex" }?.installed == true,
                  "installed state uses the package name without its dist-tag")
}

func runPluginCatalogTapgoParsing(_ runner: TestRunner) {
    let json = #"""
    {
      "available": [
        {
          "pluginId": "sparkle-publish",
          "name": "sparkle-publish",
          "displayName": "Sparkle 一键发版",
          "version": "1.0.0",
          "description": "本地 Sparkle 发布脚本与 appcast 模板",
          "repo": "https://example.invalid/sparkle-publish.git",
          "channel": "main",
          "capabilities": ["脚本", "发版"]
        },
        {
          "pluginId": "screen-recording-permission",
          "name": "screen-recording-permission",
          "version": null,
          "repo": "git@github.com:chenlaiyi/screen-recording-permission.git"
        }
      ]
    }
    """#.data(using: .utf8)!

    do {
        let items = try PluginCatalogParser.decodeTapgo(
            json,
            installedIds: ["sparkle-publish"]
        )
        runner.expectEqual(items.count, 2, "all catalog entries are decoded")
        runner.expectEqual(items.first?.name, "sparkle-publish", "installed plugin sorts first")
        runner.expectEqual(items.first?.marketplace, .tapgo, "marketplace is tapgo")
        runner.expectEqual(items.first?.displayName, "Sparkle 一键发版",
                           "explicit displayName overrides humanized name")
        runner.expectEqual(items.first?.installSpecifier,
                           "https://example.invalid/sparkle-publish.git",
                           "repo URL is used as installSpecifier")
        runner.expect(items.contains { $0.matches("recording") },
                      "search matches by description-derived name")
        runner.expectEqual(
            items.first { $0.name == "screen-recording-permission" }?.version,
            "—",
            "versionless entries keep a placeholder"
        )
        runner.expectEqual(
            items.first { $0.name == "screen-recording-permission" }?.installed,
            false,
            "absent IDs are flagged not installed"
        )
    } catch {
        runner.expect(false, "Tapgo catalog decodes: \(error)")
    }
}

func runPluginCatalogTapgoSafeId(_ runner: TestRunner) {
    let payload = #"{"available":[{"pluginId":"","name":"x","repo":"https://e/repo.git"}]}"#
    let data = payload.data(using: .utf8)!
    do {
        _ = try PluginCatalogParser.decodeTapgo(data, installedIds: [])
        runner.expect(true, "decode tolerates pluginIds at the protocol level; safety enforced at install time")
    } catch {
        runner.expect(false, "decode must not throw on the protocol alone: \(error)")
    }
    runner.expect(PluginConfigEditor.isSafePluginId("screen-recording-permission"),
                  "safe pluginId is accepted")
    runner.expect(!PluginConfigEditor.isSafePluginId("plugin with space"),
                       "whitespace identifiers are rejected")
    runner.expect(!PluginConfigEditor.isSafePluginId("plugin$injection"),
                       "shell metacharacters are rejected")
}

func runPluginCatalogRepoExample(_ runner: TestRunner) {
    // 校验 Plugins/catalog.example.json 在真实仓库结构里也能解析成功，
    // 防止 demo 协议与解析器漂移。
    let url = URL(fileURLWithPath: "Plugins/catalog.example.json")
    guard let data = try? Data(contentsOf: url) else {
        runner.expect(false, "Plugins/catalog.example.json 必须存在并可读取")
        return
    }
    do {
        let items = try PluginCatalogParser.decodeTapgo(data, installedIds: [])
        runner.expectEqual(items.count, 2, "catalog.example.json 暴露 2 条 demo 插件")
        let ids = Set(items.map { $0.id })
        runner.expect(ids.contains("tapgo:tapgo-plugin-sparkle-publish"),
                      "sparkle-publish demo 进目录")
        runner.expect(ids.contains("tapgo:tapgo-plugin-screen-permission"),
                      "screen-permission demo 进目录")
        for item in items {
            runner.expect(item.installSpecifier.hasPrefix("https://github.com/chenlaiyi/"),
                          "demo repo URL 必须指向 github.com/chenlaiyi/")
            runner.expect(item.capabilities.count >= 1,
                          "demo 必须填写 capabilities 列表")
        }
    } catch {
        runner.expect(false, "catalog.example.json 协议必须兼容 decodeTapgo: \(error)")
    }
}

/// TapgoPluginsToml：`~/.tapgo/plugins.toml` 启用/停用持久化的读写往返。
@MainActor
func runTapgoPluginsToml(_ t: TestRunner) {
    // 空文件 → 追加 [plugins] 表并写入 true
    let fresh = TapgoPluginsToml.settingEnabled(true, pluginId: "tapgo-plugin-sparkle-publish", in: "")
    t.expect(fresh?.contains("[plugins]") == true, "toml: appends [plugins] header to empty file")
    t.expect(fresh?.contains("\"tapgo-plugin-sparkle-publish\" = true") == true, "toml: writes enabled=true")

    // 解析：true 集合、注释与其它表忽略
    let sample = """
    # 注释
    [plugins]
    "a" = true
    "b" = false
    "c" = true # 行内注释

    [other]
    "d" = true
    """
    t.expectEqual(TapgoPluginsToml.enabledPluginIds(in: sample), Set(["a", "c"]), "toml: parses enabled set, ignores comments and other tables")

    // 翻转已有键：其它行原样保留
    let flipped = TapgoPluginsToml.settingEnabled(false, pluginId: "a", in: sample)
    t.expect(flipped?.contains("\"a\" = false") == true, "toml: flips existing key in place")
    t.expect(flipped?.contains("\"c\" = true") == true, "toml: preserves sibling keys")

    // 非法 pluginId 拒绝
    t.expect(TapgoPluginsToml.settingEnabled(true, pluginId: "../escape", in: "") == nil, "toml: rejects unsafe pluginId")
}
