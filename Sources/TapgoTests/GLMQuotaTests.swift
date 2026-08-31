// TapgoTests/GLMQuotaTests.swift
import Foundation
@testable import TapgoCore

/// Exercises `GLMQuotaClient`: the BigModel `monitor/usage/quota/limit`
/// response → `RateLimitsSnapshot` mapping, plus the transport/auth layer.
///
/// Fixture shape mirrors the real 2026-08-30 payload: 5h window at 19% used,
/// weekly window at 67% used, plan level "lite".
@MainActor
func runGLMQuota(_ t: TestRunner) {
    // MARK: fixture → snapshot mapping (real payload shape)
    let payload: [String: Any] = [
        "code": 200,
        "success": true,
        "data": [
            "limits": [
                ["type": "CREDIT_LIMIT", "unit": 3, "number": 5,
                 "usage": 2000, "currentValue": 385, "remaining": 1614,
                 "percentage": 19, "nextResetTime": 1_788_078_085_488.0],
                ["type": "CREDIT_LIMIT", "unit": 6, "number": 1,
                 "usage": 10000, "currentValue": 6749, "remaining": 3250,
                 "percentage": 67, "nextResetTime": 1_788_193_554_998.0],
            ],
            "level": "lite",
        ],
    ] as [String: Any]
    let data = payload["data"] as! [String: Any]
    let snap = GLMQuotaClient.build(from: data, now: Date(timeIntervalSince1970: 1_700_000_000))

    t.expectEqual(snap.primary?.usedPercent ?? -1, 19, "primary: percentage is used% (19)")
    t.expectEqual(snap.primary?.windowDurationMins ?? -1, 300, "primary: unit 3 × 5 = 5h window")
    t.expectEqual(snap.primary?.resetsAt?.timeIntervalSince1970 ?? -1,
                  1_788_078_085.488, "primary: nextResetTime ms → seconds")
    t.expectEqual(snap.secondary?.usedPercent ?? -1, 67, "secondary: percentage is used% (67)")
    t.expectEqual(snap.secondary?.windowDurationMins ?? -1, 10080, "secondary: unit 6 × 1 = weekly window")
    t.expectEqual(snap.planType ?? "", "lite", "planType: level passthrough")
    t.expectEqual(snap.planLabel ?? "", "Lite", "planLabel: level capitalized")
    t.expectNil(snap.credits, "credits: not part of the GLM payload")

    // MARK: windowMins mapping
    t.expectEqual(GLMQuotaClient.windowMins(unit: 3, number: 5), 300, "windowMins: hours → ×60")
    t.expectEqual(GLMQuotaClient.windowMins(unit: 6, number: 1), 10080, "windowMins: weeks → ×10080")
    t.expectEqual(GLMQuotaClient.windowMins(unit: 9, number: 2), 120, "windowMins: unknown unit → hourly fallback")

    // MARK: missing level tolerated → planType nil → planLabel nil
    let noLevel = GLMQuotaClient.build(from: ["limits": (data["limits"] as! [[String: Any]])], now: Date())
    t.expectNil(noLevel.planType, "no level → planType nil")

    // MARK: empty limits → empty snapshot windows
    let empty = GLMQuotaClient.build(from: ["limits": [[String: Any]]()], now: Date())
    t.expectNil(empty.primary, "empty limits → no primary window")
}

@MainActor
func runGLMQuotaClient(_ t: TestRunner) async {
    // MARK: auth file missing → clear error
    let missingPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-glm-\(UUID().uuidString).json")
    let missing = GLMQuotaClient(authPath: missingPath, transport: { _ in
        (Data(), HTTPURLResponse(url: GLMQuotaClient.quotaURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    do {
        _ = try await missing.fetchRemains()
        t.expect(false, "missing auth file should throw")
    } catch {
        t.expect(error.localizedDescription.contains("未找到 GLM 凭据文件"),
                 "missing auth file: clear error message")
    }

    // MARK: HTTP 200 happy path — Authorization header carries the raw key
    let authPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-glm-\(UUID().uuidString).json")
    try? "{\"OPENAI_API_KEY\": \"glm-test-key\"}".write(to: authPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: authPath) }

    let body = """
    {"code":200,"success":true,"data":{"limits":[
      {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":385,
       "remaining":1614,"percentage":19,"nextResetTime":1788078085488},
      {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":6749,
       "remaining":3250,"percentage":67,"nextResetTime":1788193554998}],"level":"lite"}}
    """.data(using: .utf8)!

    var capturedAuth: String?
    let ok = GLMQuotaClient(authPath: authPath) { request in
        capturedAuth = request.value(forHTTPHeaderField: "Authorization")
        return (body, HTTPURLResponse(url: GLMQuotaClient.quotaURL, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
    }
    do {
        let snap = try await ok.fetchRemains()
        t.expectEqual(snap.primary?.usedPercent ?? -1, 19, "happy path: primary 19% used")
        t.expectEqual(snap.secondary?.usedPercent ?? -1, 67, "happy path: weekly 67% used")
        t.expectEqual(snap.planLabel ?? "", "Lite", "happy path: plan label Lite")
    } catch {
        t.expect(false, "happy path should not throw: \(error)")
    }
    t.expectEqual(capturedAuth ?? "", "glm-test-key",
                  "auth header: raw key without Bearer prefix (official plugin style)")

    // MARK: ProviderRegistry in-memory key — no legacy auth file required
    var registryAuth: String?
    let registryKeyClient = GLMQuotaClient(apiKey: "glm-registry-key") { request in
        registryAuth = request.value(forHTTPHeaderField: "Authorization")
        return (body, HTTPURLResponse(url: GLMQuotaClient.quotaURL, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
    }
    do {
        let snap = try await registryKeyClient.fetchRemains()
        t.expectEqual(snap.planLabel ?? "", "Lite",
                      "provider registry key: quota response parsed")
        t.expectEqual(registryAuth ?? "", "glm-registry-key",
                      "provider registry key: raw Authorization header")
    } catch {
        t.expect(false, "provider registry key should not require auth-glm.json: \(error)")
    }

    // MARK: HTTP 500 surfaces as http error
    let fail = GLMQuotaClient(authPath: authPath) { _ in
        (Data("server boom".utf8), HTTPURLResponse(url: GLMQuotaClient.quotaURL, statusCode: 500,
                                                   httpVersion: nil, headerFields: nil)!)
    }
    do {
        _ = try await fail.fetchRemains()
        t.expect(false, "HTTP 500 should throw")
    } catch {
        t.expect(error.localizedDescription.contains("HTTP 500"), "HTTP 500: surfaced")
    }

    // MARK: business error (code != 200) surfaces code + msg
    let bizBody = Data("{\"code\":1001,\"msg\":\"鉴权失败\"}".utf8)
    let biz = GLMQuotaClient(authPath: authPath) { _ in
        (bizBody, HTTPURLResponse(url: GLMQuotaClient.quotaURL, statusCode: 200,
                                  httpVersion: nil, headerFields: nil)!)
    }
    do {
        _ = try await biz.fetchRemains()
        t.expect(false, "business error should throw")
    } catch {
        t.expect(String(describing: error).contains("1001"), "business error: code surfaced")
    }
}
