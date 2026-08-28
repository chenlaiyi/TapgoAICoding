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
      }]
    }
    """#.data(using: .utf8)!

    do {
        let items = try PluginCatalogParser.decodeCodex(json)
        runner.expectEqual(items.count, 2, "installed and available plugins are merged")
        runner.expectEqual(items.first?.name, "pdf", "installed plugins sort first")
        runner.expectEqual(items.first?.enabled, false, "disabled state is retained")
        runner.expect(items.last?.matches("FIGMA") == true, "search is case-insensitive")
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
