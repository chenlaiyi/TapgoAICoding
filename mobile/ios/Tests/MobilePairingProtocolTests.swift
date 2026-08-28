// mobile/ios/Tests/MobilePairingProtocolTests.swift
//
// 把 TapgoCore/MobilePairingTests.swift 的协议层用例搬到一份独立 main 文件，
// 这样本机（只要 Swift toolchain）就能跑：swift MobilePairingProtocolTests.swift。
//
// 用 SwiftTesting-lite 自建一个最简 expect/expectEqual，不依赖 XCTest，也不需要
// iOS SDK；与 TapgoCore 测试 449 断言共用同一份 MobilePairing 实现。

import Foundation

// MARK: - iOS 副本的 MobilePairing（同 Sources/TapgoCore/MobilePairing.swift）
// 这一行 #sourceLocation 会让编译器在编译报错时把行号映射回 Core 模块，
// 方便两端 diff 时直接对应。

// MARK: - Test runner

final class TestRunner {
    var passed = 0
    var failed = 0
    var failures: [String] = []

    func expect(_ cond: Bool, _ name: String, file: String = #file, line: Int = #line) {
        if cond { passed += 1 } else {
            failed += 1
            failures.append("[\(file.split(separator: "/").last ?? ""):\(line)] \(name)")
        }
    }
    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, file: String = #file, line: Int = #line) {
        if a == b { passed += 1 } else {
            failed += 1
            failures.append("[\(file.split(separator: "/").last ?? ""):\(line)] \(name): expected \(b), got \(a)")
        }
    }
    func expectNotNil<T>(_ a: T?, _ name: String, file: String = #file, line: Int = #line) {
        if a != nil { passed += 1 } else {
            failed += 1
            failures.append("[\(file.split(separator: "/").last ?? ""):\(line)] \(name): expected non-nil")
        }
    }
    func expectNil<T>(_ a: T?, _ name: String, file: String = #file, line: Int = #line) {
        if a == nil { passed += 1 } else {
            failed += 1
            failures.append("[\(file.split(separator: "/").last ?? ""):\(line)] \(name): expected nil")
        }
    }
}

// MARK: - 用例 (从 TapgoTests/MobilePairingTests.swift 同步)

@main
struct MobilePairingProtocolTests {
    static func main() {
        let t = TestRunner()

        // 生成 6 位码 + 字符集校验
        for _ in 0..<200 {
            let code = MobilePairing.generateCode()
            t.expectEqual(code.value.count, 6, "gen: code length is 6")
            t.expect(MobilePairing.isValidCode(code.value), "gen: code uses MobilePairing.alphabet")
        }

        // 确定性
        let fixed: UInt64 = 0xDEADBEEF_CAFEBABE
        let a = MobilePairing.generateCode(rng: { fixed })
        let b = MobilePairing.generateCode(rng: { fixed })
        t.expectEqual(a.value, b.value, "gen: deterministic with fixed rng")
        t.expectEqual(a.value.count, 6, "gen: deterministic value still 6 chars")

        // isValidCode 拒绝 / 接受
        t.expect(!MobilePairing.isValidCode(""), "valid: empty")
        t.expect(!MobilePairing.isValidCode("ABCDE"), "valid: too short")
        t.expect(!MobilePairing.isValidCode("ABCDEFG"), "valid: too long")
        t.expect(!MobilePairing.isValidCode("ABCDE0"), "valid: rejects '0'")
        t.expect(!MobilePairing.isValidCode("ABCDEO"), "valid: rejects 'O'")
        t.expect(!MobilePairing.isValidCode("ABCDEI"), "valid: rejects 'I'")
        t.expect(!MobilePairing.isValidCode("ABCDE1"), "valid: rejects '1'")
        t.expect(!MobilePairing.isValidCode("ABCDE "), "valid: rejects space")
        t.expect(MobilePairing.isValidCode("ABCDE2"), "valid: accepts '2'")
        t.expect(MobilePairing.isValidCode("HJKMNP"), "valid: accepts 'HJKMNP'")

        // TTL / remainingSeconds
        let now = Date()
        let code = MobilePairing.generateCode(ttl: 30, port: 9000, now: now)
        t.expectEqual(code.port, 9000, "code: port preserved")
        t.expect(code.isValid(at: now), "ttl: valid at issued time")
        t.expect(!code.isValid(at: now.addingTimeInterval(31)), "ttl: invalid after ttl+1s")
        t.expectEqual(code.remainingSeconds(at: now), 30, "ttl: 30s remaining at start")
        t.expectEqual(code.remainingSeconds(at: now.addingTimeInterval(29.5)), 1, "ttl: rounded up at 29.5s")
        t.expectEqual(code.remainingSeconds(at: now.addingTimeInterval(40)), 0, "ttl: 0s after expiry")

        // URL round-trip
        let url = MobilePairing.pairingURL(macDeviceId: "mac-AAA",
                                           hostname: "ChenMac",
                                           host: "192.168.1.10",
                                           code: code)
        t.expectNotNil(url, "url: builds")
        let s = url?.absoluteString ?? ""
        t.expect(s.hasPrefix("tapgo-pair://mac-AAA?"), "url: scheme + device id")
        t.expect(s.contains("code=\(code.value)"), "url: embeds code")
        t.expect(s.contains("host=192.168.1.10"), "url: embeds host")
        t.expect(s.contains("port=9000"), "url: embeds port")
        t.expect(s.contains("v=1"), "url: embeds protocol version")
        t.expect(s.hasSuffix("#ChenMac"), "url: hostname in fragment")

        let parsed = url.flatMap { MobilePairing.parseIncomingURL($0) }
        t.expectNotNil(parsed, "url: parses back")
        t.expectEqual(parsed?.macDeviceId, "mac-AAA", "url: parsed macDeviceId")
        t.expectEqual(parsed?.hostname, "ChenMac", "url: parsed hostname")
        t.expectEqual(parsed?.host, "192.168.1.10", "url: parsed host")
        t.expectEqual(parsed?.port, 9000, "url: parsed port")
        t.expectEqual(parsed?.code, code.value, "url: parsed code")
        t.expectEqual(parsed?.version, "1", "url: parsed version")

        // parseIncomingURL 拒绝坏 URL
        t.expectNil(MobilePairing.parseIncomingURL(URL(string: "https://example.com")!),
                    "parse: wrong scheme rejected")
        t.expectNil(MobilePairing.parseIncomingURL(URL(string: "tapgo-pair://mac-AAA?code=BADCODE&host=1.1.1.1&port=1&v=1")!),
                    "parse: invalid code rejected")
        t.expectNil(MobilePairing.parseIncomingURL(URL(string: "tapgo-pair://mac-AAA?code=\(code.value)&host=1.1.1.1&port=NaN&v=1")!),
                    "parse: invalid port rejected")

        // toPairedMac
        if let p = parsed {
            let mac = p.toPairedMac(now: now)
            t.expectEqual(mac.deviceId, "mac-AAA", "toPairedMac: deviceId")
            t.expectEqual(mac.hostname, "ChenMac", "toPairedMac: hostname")
            t.expectEqual(mac.host, "192.168.1.10", "toPairedMac: host")
            t.expectEqual(mac.port, 9000, "toPairedMac: port")
            t.expectEqual(mac.pairedAt, now, "toPairedMac: pairedAt uses provided now")
        }

        // State 派生
        let unpaired = MobilePairing.State.unpaired
        let mac = MobilePairing.PairedMac(deviceId: "mac-AAA", hostname: "ChenMac",
                                          host: "1.2.3.4", port: 8723, pairedAt: now)
        let paired = MobilePairing.State.paired(mac, connected: false)
        let connected = MobilePairing.State.paired(mac, connected: true)
        t.expect(!unpaired.isPaired, "state: unpaired isPaired false")
        t.expect(paired.isPaired, "state: paired isPaired true")
        t.expect(!paired.connected, "state: paired connected false")
        t.expect(connected.connected, "state: connected true")
        t.expectEqual(paired.mac?.deviceId, "mac-AAA", "state: mac deviceId")
        t.expectEqual(unpaired.mac, nil, "state: unpaired mac nil")

        print("iOS MobilePairing 协议层测试: passed=\(t.passed) failed=\(t.failed)")
        if t.failed > 0 {
            print("失败用例：")
            for f in t.failures { print("  - \(f)") }
            exit(1)
        }
        print("全部通过 ✅")
    }
}
