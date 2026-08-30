// TapgoTests/DeepSeekQuotaTests.swift
import Foundation
@testable import TapgoCore

/// Exercises `DeepSeekQuotaClient`: the `user/balance` response →
/// `RateLimitsSnapshot` (credits-only) mapping, plus transport/auth layer.
@MainActor
func runDeepSeekQuota(_ t: TestRunner) {
    // MARK: fixture → snapshot (real payload shape, CNY)
    let infos: [[String: Any]] = [[
        "currency": "CNY",
        "total_balance": "17.95",
        "granted_balance": "0.00",
        "topped_up_balance": "17.95",
    ]]
    let snap = DeepSeekQuotaClient.build(from: infos, now: Date(timeIntervalSince1970: 1_700_000_000))
    let credits = snap.credits
    t.expect(credits?.hasCredits == true, "credits: hasCredits true")
    t.expect(credits?.unlimited == false, "credits: not unlimited")
    t.expectEqual(credits?.balance ?? "", "¥17.95 CNY", "credits: balance formatted with currency")
    t.expectNil(snap.primary, "no 5h window (pay-as-you-go)")
    t.expectNil(snap.secondary, "no weekly window (pay-as-you-go)")
    t.expect(credits?.isVisible == true, "credits: visible in popover")

    // MARK: missing currency tolerated
    let noCurrency = DeepSeekQuotaClient.build(from: [["total_balance": "5.00"]], now: Date())
    t.expectEqual(noCurrency.credits?.balance ?? "", "¥5.00", "credits: missing currency → bare ¥ amount")

    // MARK: empty balance_infos → empty balance string, still no crash
    let empty = DeepSeekQuotaClient.build(from: [], now: Date())
    t.expectEqual(empty.credits?.balance ?? "x", "", "credits: empty infos → empty balance")
}

@MainActor
func runDeepSeekQuotaClient(_ t: TestRunner) async {
    // MARK: auth file missing → clear error
    let missingPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ds-\(UUID().uuidString).json")
    let missing = DeepSeekQuotaClient(authPath: missingPath, transport: { _ in
        (Data(), HTTPURLResponse(url: DeepSeekQuotaClient.balanceURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    do {
        _ = try await missing.fetchBalance()
        t.expect(false, "missing auth file should throw")
    } catch {
        t.expect(error.localizedDescription.contains("未找到 DeepSeek 凭据文件"),
                 "missing auth file: clear error message")
    }

    // MARK: happy path — Bearer header carries the key
    let authPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ds-\(UUID().uuidString).json")
    try? "{\"OPENAI_API_KEY\": \"ds-test-key\"}".write(to: authPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: authPath) }

    let body = """
    {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"17.95",
      "granted_balance":"0.00","topped_up_balance":"17.95"}]}
    """.data(using: .utf8)!

    var capturedAuth: String?
    let ok = DeepSeekQuotaClient(authPath: authPath) { request in
        capturedAuth = request.value(forHTTPHeaderField: "Authorization")
        return (body, HTTPURLResponse(url: DeepSeekQuotaClient.balanceURL, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
    }
    do {
        let snap = try await ok.fetchBalance()
        t.expectEqual(snap.credits?.balance ?? "", "¥17.95 CNY", "happy path: balance parsed")
    } catch {
        t.expect(false, "happy path should not throw: \(error)")
    }
    t.expectEqual(capturedAuth ?? "", "Bearer ds-test-key",
                  "auth header: Bearer prefix (DeepSeek official style)")

    // MARK: is_available=false surfaces as error
    let unavailBody = Data("{\"is_available\":false,\"balance_infos\":[]}".utf8)
    let unavail = DeepSeekQuotaClient(authPath: authPath) { _ in
        (unavailBody, HTTPURLResponse(url: DeepSeekQuotaClient.balanceURL, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
    }
    do {
        _ = try await unavail.fetchBalance()
        t.expect(false, "is_available=false should throw")
    } catch {
        t.expect(error.localizedDescription.contains("is_available=false"), "unavailable: surfaced")
    }

    // MARK: HTTP 401 surfaces as http error
    let fail = DeepSeekQuotaClient(authPath: authPath) { _ in
        (Data("unauthorized".utf8), HTTPURLResponse(url: DeepSeekQuotaClient.balanceURL, statusCode: 401,
                                                    httpVersion: nil, headerFields: nil)!)
    }
    do {
        _ = try await fail.fetchBalance()
        t.expect(false, "HTTP 401 should throw")
    } catch {
        t.expect(error.localizedDescription.contains("HTTP 401"), "HTTP 401: surfaced")
    }
}
