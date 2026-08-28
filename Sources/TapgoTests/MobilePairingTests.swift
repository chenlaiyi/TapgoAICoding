// TapgoTests/MobilePairingTests.swift
import Foundation
@testable import TapgoCore

@MainActor
func runMobilePairing(_ t: TestRunner) {
    // Generated code
    for _ in 0..<200 {
        let code = MobilePairing.generateCode()
        t.expectEqual(code.value.count, 6, "gen: code length is 6")
        t.expect(MobilePairing.isValidCode(code.value), "gen: code uses MobilePairing.alphabet")
    }

    // Determinism with fixed rng (date timestamps differ by µs, so compare the value only)
    let fixed: UInt64 = 0xDEADBEEF_CAFEBABE
    let a = MobilePairing.generateCode(rng: { fixed })
    let b = MobilePairing.generateCode(rng: { fixed })
    t.expectEqual(a.value, b.value, "gen: deterministic with fixed rng")
    t.expectEqual(a.value.count, 6, "gen: deterministic value still 6 chars")

    // isValidCode rejects bad inputs
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

    // PairCode TTL / remainingSeconds
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

    // parse rejects
    t.expectNil(MobilePairing.parseIncomingURL(URL(string: "https://example.com/?code=ABCDE2&host=x&port=1&v=1")!),
                "parse: wrong scheme")
    t.expectNil(MobilePairing.parseIncomingURL(URL(string: "tapgo-pair://mac?code=ABCDE0&host=x&port=1&v=1")!),
                "parse: bad code rejected")
    t.expectNil(MobilePairing.parseIncomingURL(URL(string: "tapgo-pair://mac?code=ABCDE2&host=x&v=1")!),
                "parse: missing port rejected")
    t.expectNil(MobilePairing.parseIncomingURL(URL(string: "tapgo-pair://mac?code=ABCDE2&host=x&port=1&v=2")!),
                "parse: wrong protocol version rejected")

    // State accessors
    let mac = MobilePairing.PairedMac(deviceId: "d", hostname: "h", host: "1.2.3.4", port: 1, pairedAt: Date())
    let s1 = MobilePairing.State.paired(mac, connected: false)
    let s2 = MobilePairing.State.paired(mac, connected: true)
    t.expectEqual(s1, MobilePairing.State.paired(mac, connected: false), "state: equal with same fields")
    t.expectNotEqual(s1, s2, "state: not equal when connected differs")
    t.expect(s1.isPaired, "state: paired reports isPaired")
    t.expectEqual(s1.mac, mac, "state: paired exposes mac")
    t.expect(!s1.connected, "state: paired reports connected=false")
    t.expect(s2.connected, "state: paired reports connected=true")
    t.expect(!MobilePairing.State.unpaired.isPaired, "state: unpaired reports !isPaired")
    t.expectNil(MobilePairing.State.unpaired.mac, "state: unpaired.mac is nil")

    // IncomingPayload.toPairedMac
    let p = MobilePairing.IncomingPayload(macDeviceId: "d", hostname: "h", host: "1.2.3.4", port: 5, code: "ABCDE2", version: "1")
    let mac2 = p.toPairedMac(now: now)
    t.expectEqual(mac2.deviceId, "d", "payload: deviceId")
    t.expectEqual(mac2.hostname, "h", "payload: hostname")
    t.expectEqual(mac2.host, "1.2.3.4", "payload: host")
    t.expectEqual(mac2.port, 5, "payload: port")
    t.expectEqual(mac2.pairedAt, now, "payload: pairedAt")
}
