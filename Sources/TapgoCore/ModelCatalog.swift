// TapgoCore/ModelCatalog.swift
import Foundation

/// App 内可切换的模型目录（v0.5.31 起）。
///
/// 每个模型绑定自己的 codex provider 与端点，`renderConfig()` 会把全部
/// provider 一次写进 config.toml，`thread/start` 按用户当前选择显式下发
/// `model` / `modelProvider`（对新建会话生效，进行中的会话保持原模型）。
/// wire 一律 `responses`：harness 0.149+ 已移除 `chat` wire，GLM 走的是
/// 智谱为 Codex 提供的 OpenAI Responses 协议专属端点
/// （docs.bigmodel.cn/cn/coding-plan/tool/codex）。
public enum TapgoModel: String, CaseIterable, Identifiable, Codable {
    case minimaxM3 = "MiniMax-M3"
    case glm53Flash = "GLM-5.3-Flash"

    public var id: String { rawValue }

    /// codex config.toml `[model_providers.<providerId>]` 段名，
    /// 同时是 `thread/start` 的 `modelProvider` 参数值。
    public var providerId: String {
        switch self {
        case .minimaxM3: return "minimax"
        case .glm53Flash: return "glm"
        }
    }

    /// 默认端点。MiniMax 允许用户在运行设置里覆盖，实际值由上层
    /// `TapgoConfig.effectiveBaseURL(for:)` 决定；GLM 目前固定。
    public var defaultBaseURL: String {
        switch self {
        case .minimaxM3: return "https://api.minimaxi.com/v1"
        case .glm53Flash: return "https://open.bigmodel.cn/api/v1"
        }
    }

    /// 两个模型都暴露 1M 上下文；与 config.toml 的
    /// `model_context_window` / `autoCompactTokenLimit` 保持一致。
    public var contextWindow: Int { 1_000_000 }

    /// harness 模型目录里该模型条目的 JSON 片段（不含外层包裹）。
    /// `baseInstructions` 按模型注入，让自述与实际模型一致。
    public func catalogEntryJSON(baseInstructions: String, priority: Int) -> String {
        """
            {
              "slug": "\(rawValue)",
              "display_name": "\(rawValue)",
              "description": "\(catalogDescription)",
              "default_reasoning_level": "high",
              "supported_reasoning_levels": [
                { "effort": "none", "description": "Think-Off" },
                { "effort": "high", "description": "Deep" }
              ],
              "shell_type": "shell_command",
              "visibility": "list",
              "supported_in_api": true,
              "priority": \(priority),
              "base_instructions": "\(baseInstructions)",
              "supports_reasoning_summaries": true,
              "default_reasoning_summary": "none",
              "support_verbosity": false,
              "truncation_policy": { "mode": "bytes", "limit": 10000 },
              "supports_parallel_tool_calls": false,
              "experimental_supported_tools": [],
              "input_modalities": ["text", "image"]
            }
        """
    }

    /// 目录里展示的一句描述。
    var catalogDescription: String {
        switch self {
        case .minimaxM3: return "MiniMax 官方 Coding Plan 模型。"
        case .glm53Flash: return "智谱 GLM-5.3-Flash（BigModel Coding Plan）。"
        }
    }

    /// 每个模型的 base_instructions 自述段。
    var baseInstructions: String {
        "You are Tapgo AICoding, an autonomous coding agent powered by \(rawValue). "
            + Self.sharedBaseInstructionsSuffix
    }

    /// 整份 harness 模型目录 JSON。上层（TapgoConfig.renderCatalog）
    /// 直接把它落盘到 `model-catalogs/tapgo-catalog.json`。
    public static func catalogJSON() -> String {
        let entries = allCases.enumerated().map { index, model in
            model.catalogEntryJSON(
                baseInstructions: model.baseInstructions,
                priority: index
            )
        }
        return """
        {
          "models": [
        \(entries.joined(separator: ",\n"))
          ]
        }
        """
    }

    /// 所有模型共享的行为约束（原 MiniMax 单模型目录里的固定尾巴）。
    static let sharedBaseInstructionsSuffix: String =
        "For every actionable request, inspect the current workspace and use the available tools to implement and verify the result. Never claim that tools are unavailable unless a concrete tool call failed in the current turn. Treat persistent memory only as background; the current user request and current workspace evidence always win. "
        + AgentOutputPolicy.catalogInstructions
}
