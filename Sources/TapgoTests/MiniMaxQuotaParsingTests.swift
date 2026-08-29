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

    // MARK: no 5h subscription (current_interval_total_count = 0) — primary hidden
    let noSub: [String: Any] = [
        "current_interval_total_count": 0,
        "current_interval_usage_count": 0,
        "current_weekly_total_count": 0,
        "current_weekly_usage_count": 0,
    ]
    let nSnap = MiniMaxQuotaSnapshotBuilder.build(from: noSub, now: Date())
    t.expectNil(nSnap.primary, "primary: hidden when total == 0")
    t.expectNil(nSnap.secondary, "secondary: hidden when total == 0")
    t.expectNil(nSnap.planLabel, "planLabel: hidden when no subscription")

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
    if case .http(let s)? = err500 { t.expectEqual(s, 500, "fetchRemains: HTTP 500 surfaces") }
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
    if case .business(let code, _)? = errBiz { t.expectEqual(code, 1008, "fetchRemains: business error 1008 surfaces") }
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
    if case .noMatchingModel(let name)? = errNoEntry { t.expectEqual(name, "MiniMax-M3", "fetchRemains: missing model surfaces") }
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
