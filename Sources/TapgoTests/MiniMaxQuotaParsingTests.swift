import Foundation
@testable import TapgoCore

/// Exercises `MiniMaxQuotaSnapshotBuilder`, the conversion layer that takes a
/// single entry from MiniMax's `model_remains` array and returns a
/// `RateLimitsSnapshot` matching the popover's expected shape.
///
/// The non-obvious bit: MiniMax's `current_interval_usage_count` /
/// `current_weekly_usage_count` are "remaining" (NOT used). The builder must
/// invert this before producing `usedPercent`.
@MainActor
func runMiniMaxQuotaParsing(_ t: TestRunner) {
    // MARK: basic reverse — 4500 total / 404 remaining → 91% used
    let basic: [String: Any] = [
        "model_name": "MiniMax-M3",
        "current_interval_total_count": 4500,
        "current_interval_usage_count": 404,           // remaining
        "current_weekly_total_count": 157_500,
        "current_weekly_usage_count": 155_640,         // remaining
        "end_time": 1_756_660_800,
        "plan_name": "Plus",
    ]
    let snap = MiniMaxQuotaSnapshotBuilder.build(from: basic, now: Date(timeIntervalSince1970: 1_700_000_000))
    t.expectEqual(snap.primary?.usedPercent ?? -1, 91, "primary: (4500-404)/4500 ≈ 91%")
    t.expectEqual(snap.primary?.windowDurationMins ?? -1, 300, "primary: 5h window")
    t.expectEqual(snap.primary?.resetsAt?.timeIntervalSince1970 ?? -1, 1_756_660_800, "primary: end_time passes through")
    t.expectEqual(snap.secondary?.usedPercent ?? -1, 1, "secondary: (157500-155640)/157500 ≈ 1%")
    t.expectEqual(snap.secondary?.windowDurationMins ?? -1, 10080, "secondary: weekly window")
    t.expectNil(snap.secondary?.resetsAt, "secondary: weekly resetsAt not provided")
    t.expectEqual(snap.planLabel ?? "", "Plus", "planLabel: passthrough")
    t.expectNil(snap.credits, "credits: hidden for Token Plan subscription")

    // MARK: full depletion — 4500 total / 0 remaining → 100% used (clamped)
    let depleted: [String: Any] = [
        "current_interval_total_count": 4500,
        "current_interval_usage_count": 0,
    ]
    let dSnap = MiniMaxQuotaSnapshotBuilder.build(from: depleted, now: Date())
    t.expectEqual(dSnap.primary?.usedPercent ?? -1, 100, "primary: full depletion → 100%")

    // MARK: untouched — 4500 total / 4500 remaining → 0% used
    let untouched: [String: Any] = [
        "current_interval_total_count": 4500,
        "current_interval_usage_count": 4500,
    ]
    let uSnap = MiniMaxQuotaSnapshotBuilder.build(from: untouched, now: Date())
    t.expectEqual(uSnap.primary?.usedPercent ?? -1, 0, "primary: untouched → 0%")

    // MARK: weird overshoot — total smaller than remaining (server glitch)
    //         builder must clamp to 100%, not produce negative %.
    let glitch: [String: Any] = [
        "current_interval_total_count": 100,
        "current_interval_usage_count": 250,
    ]
    let gSnap = MiniMaxQuotaSnapshotBuilder.build(from: glitch, now: Date())
    t.expectEqual(gSnap.primary?.usedPercent ?? -1, 100, "primary: server glitch → clamped to 100%")

    // MARK: no quota total — 但 remaining_percent 仍给值（账户无具体 quota 时的
    //       "subscription level" 字段），primary 应当显示 usedPercent = 100 - remaining%。
    let noSub: [String: Any] = [
        "current_interval_total_count": 0,
        "current_interval_usage_count": 0,
        "current_interval_remaining_percent": 89,
        "current_weekly_total_count": 0,
        "current_weekly_usage_count": 0,
        "current_weekly_remaining_percent": 74,
    ]
    let nSnap = MiniMaxQuotaSnapshotBuilder.build(from: noSub, now: Date())
    t.expectEqual(nSnap.primary?.usedPercent ?? -1, 11, "primary: total=0 但 remaining_percent=89 → usedPercent=11")
    t.expectEqual(nSnap.secondary?.usedPercent ?? -1, 26, "secondary: total=0 但 remaining_percent=74 → usedPercent=26")
    t.expectNil(nSnap.planLabel, "planLabel: hidden when no subscription")

    // 完全没 total 也没 percent → primary/secondary 都隐藏。
    let totallyEmpty: [String: Any] = [
        "current_interval_total_count": 0,
        "current_interval_usage_count": 0,
        "current_weekly_total_count": 0,
        "current_weekly_usage_count": 0,
    ]
    let teSnap = MiniMaxQuotaSnapshotBuilder.build(from: totallyEmpty, now: Date())
    t.expectNil(teSnap.primary, "primary: hidden when total==0 AND no percent")
    t.expectNil(teSnap.secondary, "secondary: hidden when total==0 AND no percent")

    // total > 0 但 percent 同时存在 — 优先用 percent（更可靠，避免服务端 total/usage 不一致）。
    let totalAndPct: [String: Any] = [
        "current_interval_total_count": 1000,
        "current_interval_usage_count": 800,    // remaining=800, 但 percent=25 表示只用了 75%
        "current_interval_remaining_percent": 25,
    ]
    let tpSnap = MiniMaxQuotaSnapshotBuilder.build(from: totalAndPct, now: Date())
    t.expectEqual(tpSnap.primary?.usedPercent ?? -1, 75, "primary: 同时有 percent 和 total/usage → 优先 percent=25 → used=75")

    // MARK: plan_name whitespace trimmed & dropped when empty
    let blankPlan: [String: Any] = [
        "current_interval_total_count": 100,
        "current_interval_usage_count": 50,
        "plan_name": "   ",
    ]
    let bSnap = MiniMaxQuotaSnapshotBuilder.build(from: blankPlan, now: Date())
    t.expectNil(bSnap.planLabel, "planLabel: blank → hidden")

    // MARK: numeric type tolerance — server sometimes returns NSNumber / Double / String
    let numeric: [String: Any] = [
        "current_interval_total_count": NSNumber(value: 200),
        "current_interval_usage_count": NSNumber(value: 50.0),
    ]
    let n2Snap = MiniMaxQuotaSnapshotBuilder.build(from: numeric, now: Date())
    t.expectEqual(n2Snap.primary?.usedPercent ?? -1, 75, "primary: numeric coercion (NSNumber/Double) → 75%")
}

/// Exercises `MiniMaxQuotaClient.fetchRemains` end-to-end against a fake
/// transport, including auth-file bootstrap and the 200-with-bad-status guard.
@MainActor
func runMiniMaxQuotaClient(_ t: TestRunner) async {
    // Write a throwaway auth.json so the client can read OPENAI_API_KEY.
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-minimax-quota-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let authPath = tmpDir.appendingPathComponent("auth.json")
    try? FileManager.default.removeItem(at: authPath)
    let auth: [String: Any] = ["OPENAI_API_KEY": "sk-cp-fake-test-key"]
    guard let authData = try? JSONSerialization.data(withJSONObject: auth) else {
        t.expect(false, "auth.json 写入失败"); return
    }
    do { try authData.write(to: authPath) } catch {
        t.expect(false, "auth.json 写入失败: \(error)"); return
    }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let modelName = "MiniMax-M3"
    var capturedAuthHeader: String?

    // Fake transport — checks Authorization header & returns canned JSON.
    let transport: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        capturedAuthHeader = req.value(forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "success"],
            "model_remains": [[
                "model_name": modelName,
                "current_interval_total_count": 1000,
                "current_interval_usage_count": 250,
                "current_weekly_total_count": 8000,
                "current_weekly_usage_count": 4000,
                "end_time": 1_756_660_800,
                "plan_name": "Plus",
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }

    let client = MiniMaxQuotaClient(
        region: .china,
        authPath: authPath,
        modelName: modelName,
        transport: transport
    )
    let snap = try? await client.fetchRemains(now: Date(timeIntervalSince1970: 1_700_000_000))
    t.expectNotNil(snap, "fetchRemains: success")
    t.expectEqual(capturedAuthHeader ?? "", "Bearer sk-cp-fake-test-key", "transport: Bearer header from auth.json")
    t.expectEqual(snap?.primary?.usedPercent ?? -1, 75, "primary: 1000 total / 250 remaining → 75% used")
    t.expectEqual(snap?.secondary?.usedPercent ?? -1, 50, "secondary: 8000 total / 4000 remaining → 50% used")
    t.expectEqual(snap?.planLabel ?? "", "Plus", "planLabel: Plus")

    // MARK: HTTP error → surfaced
    let transport500: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(), resp)
    }
    let c500 = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: modelName, transport: transport500
    )
    var err500: MiniMaxQuotaClient.QuotaError?
    do { _ = try await c500.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { err500 = e } catch { err500 = nil }
    if case .http(let s, _)? = err500 { t.expectEqual(s, 500, "fetchRemains: HTTP 500 surfaces") }
    else { t.expect(false, "fetchRemains: HTTP 500 expected QuotaError.http") }

    // MARK: business error → surfaced (status_code != 0 with 200 HTTP)
    let transportBiz: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let body: [String: Any] = [
            "base_resp": ["status_code": 1008, "status_msg": "insufficient balance"],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }
    let cBiz = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: modelName, transport: transportBiz
    )
    var errBiz: MiniMaxQuotaClient.QuotaError?
    do { _ = try await cBiz.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { errBiz = e } catch { errBiz = nil }
    if case .business(let code, _, _)? = errBiz { t.expectEqual(code, 1008, "fetchRemains: business error 1008 surfaces") }
    else { t.expect(false, "fetchRemains: business error expected QuotaError.business") }

    // MARK: no model entry → noMatchingModel
    let transportNoEntry: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let body: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "success"],
            "model_remains": [
                ["model_name": "MiniMax-OtherModel",
                 "current_interval_total_count": 100,
                 "current_interval_usage_count": 50],
                ["model_name": "MiniMax-DifferentModel",
                 "current_interval_total_count": 200,
                 "current_interval_usage_count": 100],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }
    let cNoEntry = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: modelName, transport: transportNoEntry
    )
    var errNoEntry: MiniMaxQuotaClient.QuotaError?
    do { _ = try await cNoEntry.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { errNoEntry = e } catch { errNoEntry = nil }
    if case .noMatchingModel(let name, _, _)? = errNoEntry { t.expectEqual(name, "MiniMax-M3", "fetchRemains: missing model surfaces") }
    else { t.expect(false, "fetchRemains: missing model expected QuotaError.noMatchingModel") }

    // MARK: missing auth.json → missingAuthFile
    let missingAuthPath = tmpDir.appendingPathComponent("does-not-exist.json")
    let cMissing = MiniMaxQuotaClient(
        region: .china, authPath: missingAuthPath, modelName: modelName,
        transport: transport
    )
    var errMissing: MiniMaxQuotaClient.QuotaError?
    do { _ = try await cMissing.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { errMissing = e } catch { errMissing = nil }
    if case .missingAuthFile? = errMissing { t.expect(true, "fetchRemains: missing auth.json surfaces") }
    else { t.expect(false, "fetchRemains: missing auth.json expected QuotaError.missingAuthFile") }

    // MARK: single-entry response → wildcard fallback (no matching model_name)
    let transportWildcard: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let body: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "success"],
            "model_remains": [[
                "model_name": "Different-Name",
                "current_interval_total_count": 500,
                "current_interval_usage_count": 100,
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }
    let cWild = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: modelName, transport: transportWildcard
    )
    let wildSnap = try? await cWild.fetchRemains()
    t.expectEqual(wildSnap?.primary?.usedPercent ?? -1, 80, "fetchRemains: single-entry → wildcard fallback (500-100)/500 = 80%")
}


/// Exercises the lenient model-name matching + dual-endpoint fallback that
/// fix v0.5.25 introduced after the user reported `noMatchingModel` with
/// unhelpful diagnostics.
@MainActor
func runMiniMaxQuotaLenientMatch(_ t: TestRunner) async {
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-minimax-lenient-(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let authPath = tmpDir.appendingPathComponent("auth.json")
    if let authData = try? JSONSerialization.data(withJSONObject: ["OPENAI_API_KEY": "sk-cp-x"]) {
        try? authData.write(to: authPath)
    }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // 不同 model_name 写法都能命中目标模型。
    let variants: [(name: String, label: String)] = [
        ("MiniMax-M3", "hyphen, brand-prefixed"),
        ("minimax-m3", "lowercase, hyphen"),
        ("MiniMax M3", "space separator"),
        ("MiniMax_M3", "underscore separator"),
        ("MiniMax.M3", "dot separator"),
        ("M3",          "bare short name"),
        ("MiniMax M2.7","wrong model — must NOT match"),
        ("general",     "MiniMax quota category for chat models"),
    ]
    for v in variants {
        let transport: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
            // 必须只能命中 coding_plan 端点；token_plan 端点返回 200 但 model_remains 为空。
            let path = req.url?.path ?? ""
            let body: [String: Any]
            if path.contains("coding_plan") {
                if v.label.contains("category for chat") {
                    // "general" 是 MiniMax 对所有文本模型的 quota 分桶, server 返回结构照搬真实接口
                    body = [
                        "base_resp": ["status_code": 0, "status_msg": "success"],
                        "model_remains": [
                            ["model_name": "general",
                             "current_interval_total_count": 1000,
                             "current_interval_usage_count": 250,
                             "current_interval_remaining_percent": 75],
                            ["model_name": "video",
                             "current_interval_total_count": 5,
                             "current_interval_usage_count": 0,
                             "current_interval_remaining_percent": 100],
                        ],
                    ]
                } else {
                    body = [
                        "base_resp": ["status_code": 0, "status_msg": "success"],
                        "model_remains": [[
                            "model_name": v.name,
                            "current_interval_total_count": 1000,
                            "current_interval_usage_count": 250,
                        ]],
                    ]
                }
            } else {
                body = [
                    "base_resp": ["status_code": 0, "status_msg": "success"],
                    "model_remains": [],
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: body)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (data, resp)
        }
        let client = MiniMaxQuotaClient(
            region: .china, authPath: authPath, modelName: "MiniMax-M3",
            transport: transport
        )
        if v.label.contains("wrong") {
            // 单条目会被通配兜底; 用 2 条配置才能验证严格匹配。
            let transportTwo: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
                let body: [String: Any] = [
                    "base_resp": ["status_code": 0, "status_msg": "success"],
                    "model_remains": [
                        ["model_name": v.name,
                         "current_interval_total_count": 1000,
                         "current_interval_usage_count": 250],
                        ["model_name": "MiniMax-TTS",
                         "current_interval_total_count": 100,
                         "current_interval_usage_count": 50],
                    ],
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (data, resp)
            }
            let strictClient = MiniMaxQuotaClient(
                region: .china, authPath: authPath, modelName: "MiniMax-M3",
                transport: transportTwo
            )
            let snap = try? await strictClient.fetchRemains()
            t.expectNil(snap, "lenient (严格, 2 条配置): (v.label) → 不应命中")
        } else {
            let snap = try? await client.fetchRemains()
            t.expectNotNil(snap, "lenient: (v.label) → 命中")
            // "general" 桶返回 remaining_percent=75 → usedPercent=25; 其余变体走
            // total - remaining 反算 → 75。
            if v.label.contains("category for chat") {
                t.expectEqual(snap?.primary?.usedPercent ?? -1, 25, "lenient: (v.label) → remaining_percent=75 → used=25%")
            } else {
                t.expectEqual(snap?.primary?.usedPercent ?? -1, 75, "lenient: (v.label) → 75% used")
            }
        }
    }

    // 诊断信息: noMatchingModel 应包含接口实际返回的 model_name 列表。
    let transportDiagnostic: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let body: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "success"],
            "model_remains": [
                ["model_name": "MiniMax-M2.7",
                 "current_interval_total_count": 500, "current_interval_usage_count": 100],
                ["model_name": "MiniMax-TTS",
                 "current_interval_total_count": 100, "current_interval_usage_count": 50],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }
    let client = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: "MiniMax-M3",
        transport: transportDiagnostic
    )
    var err: MiniMaxQuotaClient.QuotaError?
    do { _ = try await client.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { err = e } catch {}
    // 两条端点都试 —— coding_plan 返回 noMatchingModel, token_plan 单条会被通配命中返回 RateLimitsSnapshot。
    // 检查返回的端点路径包含 coding_plan 即可 (因为 token_plan 那条因为单条会通配命中)。
    if case .noMatchingModel(_, let returned, let endpoint)? = err {
        t.expect(returned.contains("MiniMax-M2.7"), "diagnostic (noMatchingModel): 返回列表包含 M2.7")
        t.expect(returned.contains("MiniMax-TTS"), "diagnostic (noMatchingModel): 返回列表包含 TTS")
        t.expect(endpoint.contains("coding_plan") || endpoint.contains("token_plan"),
                 "diagnostic (noMatchingModel): 端点路径出现, got (endpoint)")
    } else if case .emptyResponse(let endpoint)? = err {
        t.expect(endpoint.contains("token_plan") || endpoint.contains("coding_plan"),
                 "diagnostic (emptyResponse): 端点路径出现, got (endpoint)")
    } else {
        t.expect(false, "diagnostic: 期望 noMatchingModel 或 emptyResponse, 实际 (String(describing: err))")
    }

    // 完全空响应 → emptyResponse
    let transportEmpty: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
        let body: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "success"],
            "model_remains": []
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, resp)
    }
    let emptyClient = MiniMaxQuotaClient(
        region: .china, authPath: authPath, modelName: "MiniMax-M3",
        transport: transportEmpty
    )
    var emptyErr: MiniMaxQuotaClient.QuotaError?
    do { _ = try await emptyClient.fetchRemains() } catch let e as MiniMaxQuotaClient.QuotaError { emptyErr = e } catch {}
    if case .emptyResponse? = emptyErr {
        t.expect(true, "emptyResponse: 两条端点都返回空 → 抛出 emptyResponse")
    } else {
        t.expect(false, "emptyResponse: 期望 emptyResponse, 实际 (String(describing: emptyErr))")
    }
}


/// 验证 MiniMax 接口的毫秒级 Unix 时间戳能正确解析。
/// 真实接口给的 end_time 是 13 位毫秒 (如 1788019200000), 而 Codex 协议是
/// 10 位秒级; dateValue 必须正确处理两种格式, 否则『重置于』会显示到几千年后。
@MainActor
func runMiniMaxQuotaTimestampParsing(_ t: TestRunner) {
    // 毫秒级 (MiniMax 接口实际格式): 1788019200000 = 2026-08-29 16:00 UTC
    let ms: [String: Any] = [
        "current_interval_total_count": 1000,
        "current_interval_usage_count": 250,
        "end_time": 1_788_019_200_000,  // ms
    ]
    let msSnap = MiniMaxQuotaSnapshotBuilder.build(from: ms, now: Date(timeIntervalSince1970: 0))
    let msExpected = TimeInterval(1_788_019_200_000 / 1000)
    t.expectEqual(msSnap.primary?.resetsAt?.timeIntervalSince1970 ?? -1,
                 msExpected, "ms timestamp: end_time=1788019200000 → 2026-08-29")

    // 秒级 (Codex 协议格式, 也兼容处理): 1756660800 = 2025-09-01
    let s: [String: Any] = [
        "current_interval_total_count": 1000,
        "current_interval_usage_count": 250,
        "end_time": 1_756_660_800,  // s
    ]
    let sSnap = MiniMaxQuotaSnapshotBuilder.build(from: s, now: Date(timeIntervalSince1970: 0))
    t.expectEqual(sSnap.primary?.resetsAt?.timeIntervalSince1970 ?? -1,
                 1_756_660_800, "s timestamp: end_time=1756660800 → 2025-09-01 (兼容秒级)")
}

