import Foundation

/// MobileRemoteLink 协议层测试 (JSON-RPC over TCP 帧定义)。
@main
@MainActor
struct MobileRemoteLinkTests {
    static func main() {
        do { try runAll() }
        catch { print("THROW: \(error)"); exit(1) }
    }
    static func runAll() throws {
        var passed = 0, failed = 0
        func check(_ cond: Bool, _ name: String) {
            if cond { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
        }

        // 1. Frame round-trip: request
        do {
            var p = MobileRemoteLink.Params()
            p.set("name", .string("hello"))
            p.set("count", .int(3))
            p.set("ok", .bool(true))
            let f = MobileRemoteLink.makeRequest(method: "echo", params: p)
            let data = try MobileRemoteLink.encode(f)
            let back = try MobileRemoteLink.decode(data)
            check(back.id != nil, "request has id")
            check(back.method == "echo", "request method")
            check(back.params?["name"]?.stringValue == "hello", "params.string")
            check(back.params?["count"]?.intValue == 3, "params.int")
            check(back.params?["ok"]?.boolValue == true, "params.bool")
        }

        // 2. Frame round-trip: result
        do {
            var p = MobileRemoteLink.Params()
            p.set("ok", .bool(true))
            let f = MobileRemoteLink.makeResult(id: "abc", result: p)
            let data = try MobileRemoteLink.encode(f)
            let back = try MobileRemoteLink.decode(data)
            check(back.id == "abc", "result id")
            check(back.result?["ok"]?.boolValue == true, "result content")
            check(back.method == nil, "result no method")
        }

        // 3. Frame round-trip: error
        do {
            let f = MobileRemoteLink.makeError(id: "abc", code: 42, message: "oops")
            let data = try MobileRemoteLink.encode(f)
            let back = try MobileRemoteLink.decode(data)
            check(back.error?.code == 42, "error code")
            check(back.error?.message == "oops", "error message")
        }

        // 4. Frame round-trip: push
        do {
            let f = MobileRemoteLink.makeHello(deviceId: "mac-001")
            let data = try MobileRemoteLink.encode(f)
            let back = try MobileRemoteLink.decode(data)
            check(back.id == nil, "push no id")
            check(back.method == "hello", "push method")
            check(back.isPush, "isPush true")
        }

        // 5. isRequest / isResponse / isPush 分类正确
        do {
            let req = MobileRemoteLink.makeRequest(method: "x")
            check(req.isRequest && !req.isPush, "request category")
            let resp = MobileRemoteLink.makeResult(id: "1", result: .init())
            check(resp.isResponse && !req.isPush, "response category")
            let push = MobileRemoteLink.makeHeartbeat()
            check(push.isPush && !push.isRequest && !push.isResponse, "push category")
        }

        // 6. encode 不带尾巴换行; 调用方自己加 \n
        do {
            let f = MobileRemoteLink.makeHeartbeat()
            let data = try MobileRemoteLink.encode(f)
            check(data.last != 0x0A, "encode no trailing newline")
        }

        // 7. AnyJSON 嵌套: array + object
        do {
            var inner = MobileRemoteLink.Params()
            inner.set("k", .string("v"))
            var outer = MobileRemoteLink.Params()
            outer.set("list", .array([.int(1), .int(2), .string("three")]))
            outer.set("nested", .object(inner.raw))
            let f = MobileRemoteLink.makeRequest(method: "m", params: outer)
            let data = try MobileRemoteLink.encode(f)
            let back = try MobileRemoteLink.decode(data)
            check(back.params?["list"] != nil, "nested list")
            check(back.params?["nested"]?["k"]?.stringValue == "v", "nested object")
        }

        // 8. bonjour service type / default port 常量
        do {
            check(MobileRemoteLink.bonjourServiceType == "_tapgo-pair._tcp", "bonjour type")
            check(MobileRemoteLink.defaultPort == 8723, "default port")
            check(MobileRemoteLink.protocolVersion == 1, "protocol version")
        }

        print("MobileRemoteLink 测试: passed=\(passed) failed=\(failed)")
        if failed > 0 { exit(1) }
    }
}
