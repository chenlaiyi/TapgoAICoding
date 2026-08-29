// TapgoTests/PhoneRemoteTests.swift
// v0.5.16 "扫码即开 H5" 移动端远程控制 — 协议层 (TapgoCore/PhoneRemoteLink.swift) 回归。
import Foundation
@testable import TapgoCore

// MARK: - token

func runPhoneRemoteToken(_ t: TestRunner) {
    for _ in 0..<200 {
        let token = PhoneRemote.makeToken()
        t.expectEqual(token.count, 22, "token: 长度恒为 22")
        t.expect(PhoneRemote.isValidToken(token), "token: 生成即可通过校验")
        t.expect(!token.contains("+") && !token.contains("/") && !token.contains("="),
                 "token: base64url 字符集 (无 +/ =)")
    }
    var seen = Set<String>()
    for _ in 0..<200 { seen.insert(PhoneRemote.makeToken()) }
    t.expectEqual(seen.count, 200, "token: 200 次生成无碰撞")

    t.expect(!PhoneRemote.isValidToken(""), "token: 空串非法")
    t.expect(!PhoneRemote.isValidToken("abc"), "token: 过短非法")
    t.expect(!PhoneRemote.isValidToken(String(repeating: "A", count: 23)), "token: 过长非法")
    t.expect(!PhoneRemote.isValidToken(String(repeating: "A", count: 21) + "+"), "token: 拒绝 +")
    t.expect(!PhoneRemote.isValidToken(String(repeating: "A", count: 21) + "/"), "token: 拒绝 /")
    t.expect(PhoneRemote.isValidToken(String(repeating: "a", count: 22)), "token: 接受 22 位字母")
    t.expect(PhoneRemote.isValidToken(String(repeating: "-", count: 22)), "token: 接受 base64url -")
}

// MARK: - 链接 + 路由

func runPhoneRemoteLinkRoute(_ t: TestRunner) {
    let token = PhoneRemote.makeToken()
    let url = PhoneRemote.linkURL(host: "192.168.1.5", port: 8723, token: token)
    t.expect(url != nil, "link: 合法输入可构建 URL")
    t.expectEqual(url?.absoluteString ?? "", "http://192.168.1.5:8723/r/\(token)",
                  "link: 形如 http://<ip>:<port>/r/<token>")
    t.expect(PhoneRemote.linkURL(host: "192.168.1.5", port: 8723, token: "bad") == nil,
             "link: 非法 token 拒绝构建 URL")

    func route(_ method: String, _ path: String, _ body: String = "",
               expected: String = token) -> Result<PhoneRemote.Route, PhoneRemote.RouteError> {
        PhoneRemote.route(method: method, path: path, body: Data(body.utf8), expectedToken: expected)
    }

    if case .success(.page) = route("GET", "/r/\(token)") {} else {
        t.expect(false, "route: GET /r/<token> → page")
    }
    if case .success(.page) = route("GET", "/r/\(token)/") {} else {
        t.expect(false, "route: GET /r/<token>/ → page")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/") {} else {
        t.expect(false, "route: POST 页面路径 → badRequest")
    }
    if case .success(.state) = route("GET", "/r/\(token)/api/state") {} else {
        t.expect(false, "route: GET api/state → state")
    }
    if case .failure(.badRequest) = route("PUT", "/r/\(token)/api/state") {} else {
        t.expect(false, "route: PUT api/state → badRequest")
    }
    if case .success(.send(let text)) = route("POST", "/r/\(token)/api/send", #"{"text":"你好 world"}"#) {
        t.expectEqual(text, "你好 world", "route: send 携带 UTF-8 文本")
    } else {
        t.expect(false, "route: POST api/send → send")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/send", #"{"text":""}"#) {} else {
        t.expect(false, "route: 空文本 send → badRequest")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/send", "not json") {} else {
        t.expect(false, "route: 非 JSON body → badRequest")
    }
    if case .success(.select(let id)) = route("POST", "/r/\(token)/api/select", #"{"threadId":"th9"}"#) {
        t.expectEqual(id, "th9", "route: select 携带 threadId")
    } else {
        t.expect(false, "route: POST api/select → select")
    }
    if case .failure(.notFound) = route("GET", "/r/\(token)/api/nope") {} else {
        t.expect(false, "route: 未知 api 路径 → notFound")
    }
    if case .failure(.notFound) = route("GET", "/elsewhere/\(token)") {} else {
        t.expect(false, "route: 非 /r 前缀 → notFound")
    }

    // 错误 token → unauthorized (拒绝优先于 notFound)
    let stranger = PhoneRemote.makeToken()
    if case .failure(.unauthorized) = route("GET", "/r/\(stranger)/", expected: token) {} else {
        t.expect(false, "route: token 不符 → unauthorized")
    }
    if case .failure(.unauthorized) = route("GET", "/r/\(stranger)/api/state", expected: token) {} else {
        t.expect(false, "route: token 不符的 api 调用 → unauthorized")
    }

    // 常量时间比对
    t.expect(PhoneRemote.constantTimeEquals("abc", "abc"), "ctEqual: 相等")
    t.expect(!PhoneRemote.constantTimeEquals("abc", "abd"), "ctEqual: 不等")
    t.expect(!PhoneRemote.constantTimeEquals("abc", "ab"), "ctEqual: 长度不等")
}

// MARK: - HTTP 解析与响应

func runPhoneRemoteHTTP(_ t: TestRunner) {
    // GET 带 query
    let getReq = Data("GET /r/abc/api/state?rev=7 HTTP/1.1\r\nHost: 192.168.1.5:8723\r\nAccept: */*\r\n\r\n".utf8)
    guard let get = PhoneRemote.parseRequest(getReq) else {
        t.expect(false, "http: GET 可解析"); return
    }
    t.expectEqual(get.method, "GET", "http: GET method")
    t.expectEqual(get.path, "/r/abc/api/state", "http: query string 不进 path")
    t.expect(get.body.isEmpty, "http: GET 无 body")

    // 不完整 (未收到 \r\n\r\n) → nil, 继续等
    let partial = Data("GET /r/abc HTTP/1.1\r\nHost: x".utf8)
    t.expect(PhoneRemote.parseRequest(partial) == nil, "http: 头未到齐返回 nil 等待更多数据")

    // POST + Content-Length body (中文多字节)
    let body = Data(#"{"text":"你好"}"#.utf8)
    var post = Data("POST /r/abc/api/send HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
    post.append(body)
    guard let parsed = PhoneRemote.parseRequest(post) else {
        t.expect(false, "http: POST 可解析"); return
    }
    t.expectEqual(parsed.method, "POST", "http: POST method")
    t.expectEqual(parsed.body, body, "http: body 按 Content-Length 精确截取")

    // Content-Length 声明大于已到字节 → 等待
    var partialBody = Data("POST /r/abc/api/send HTTP/1.1\r\nContent-Length: 100\r\n\r\n{\"text\"".utf8)
    t.expect(PhoneRemote.parseRequest(partialBody) == nil, "http: body 未到齐返回 nil")

    // 超限检测
    partialBody.append(Data(repeating: 0x61, count: PhoneRemote.maxHeadBytes + PhoneRemote.maxBodyBytes))
    t.expect(PhoneRemote.isRequestOversized(partialBody), "http: 超限可检测 (用于断开)")

    // 响应序列化
    let resp = PhoneRemote.httpResponse(status: 200, reason: "OK",
                                        contentType: "text/html; charset=utf-8",
                                        body: Data("hi".utf8))
    let text = String(decoding: resp, as: UTF8.self)
    t.expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"), "http: 状态行")
    t.expect(text.contains("Content-Type: text/html; charset=utf-8\r\n"), "http: Content-Type")
    t.expect(text.contains("Content-Length: 2\r\n"), "http: Content-Length 与 body 一致")
    t.expect(text.contains("Connection: close\r\n"), "http: 固定短连接")
    t.expect(text.hasSuffix("\r\n\r\nhi"), "http: 头体以空行分隔")

    let forbidden = String(decoding: PhoneRemote.forbiddenResponse, as: UTF8.self)
    t.expect(forbidden.hasPrefix("HTTP/1.1 403"), "http: 403 响应")
    let nf = String(decoding: PhoneRemote.notFoundResponse, as: UTF8.self)
    t.expect(nf.hasPrefix("HTTP/1.1 404"), "http: 404 响应")
}

// MARK: - 状态快照

func runPhoneRemoteSnapshot(_ t: TestRunner) {
    let now = Date()
    let longText = String(repeating: "长", count: PhoneRemote.maxTextLength + 500)

    let turns = [
        Turn(id: "t1", userInput: "帮我修复构建",
             items: [
                .assistantMessage(id: "app-progress-1", text: "进度提示应被剔除"),
                .assistantMessage(id: "m1", text: "已修复。"),
             ],
             status: .completed, startedAt: now),
        Turn(id: "t2", userInput: longText,
             items: [.assistantMessage(id: "m2", text: "好的")],
             status: .running, startedAt: now),
    ]
    let active = Thread(id: "th1", title: "修复构建", createdAt: now, updatedAt: now, turns: turns)
    let other = Thread(id: "th2", title: "另一个会话",
                       createdAt: now, updatedAt: now.addingTimeInterval(-600), turns: [])

    let snap = PhoneRemote.buildState(threads: [other, active],
                                      activeId: "th1",
                                      rev: 7,
                                      hostname: "Chenlaiyi",
                                      appVersion: "0.5.16",
                                      now: now)
    t.expectEqual(snap.rev, 7, "snapshot: rev 透传")
    t.expectEqual(snap.hostname, "Chenlaiyi", "snapshot: hostname 透传")
    t.expectEqual(snap.linkVersion, PhoneRemote.linkVersion, "snapshot: linkVersion")
    // 会话按 updatedAt 最新在前
    t.expectEqual(snap.threads.count, 2, "snapshot: 会话数")
    t.expectEqual(snap.threads.first?.id, "th1", "snapshot: 最新会话排前")
    t.expectEqual(snap.threads.first?.busy, true, "snapshot: 最近 turn 运行中 → busy")
    t.expectEqual(snap.threads.last?.busy, false, "snapshot: 空会话不 busy")
    t.expectEqual(snap.activeId, "th1", "snapshot: activeId 透传")

    // transcript: app-progress 剔除 + 截断 + running 标记
    t.expectEqual(snap.transcript.count, 2, "snapshot: transcript 条数")
    t.expectEqual(snap.transcript[0].assistant, "已修复。", "snapshot: app-progress- 前缀剔除")
    t.expectEqual(snap.transcript[1].running, true, "snapshot: running turn 标记")
    t.expectEqual(snap.transcript[1].user.count, PhoneRemote.maxTextLength + "\n…(已截断)".count,
                  "snapshot: 超长文本截断")

    // 无 activeId 时回落第一个会话
    let fallback = PhoneRemote.buildState(threads: [other], activeId: nil, rev: 0,
                                          hostname: "h", appVersion: "v", now: now)
    t.expectEqual(fallback.activeId, "th2", "snapshot: activeId 缺省回落首个会话")

    // transcript 只带最近 maxTranscriptTurns 条
    var many: [Turn] = []
    for i in 0..<(PhoneRemote.maxTranscriptTurns + 10) {
        many.append(Turn(id: "n\(i)", userInput: "u\(i)", status: .completed, startedAt: now))
    }
    let big = Thread(id: "th3", title: "长会话", createdAt: now, updatedAt: now, turns: many)
    let bigSnap = PhoneRemote.buildState(threads: [big], activeId: "th3", rev: 0,
                                         hostname: "h", appVersion: "v", now: now)
    t.expectEqual(bigSnap.transcript.count, PhoneRemote.maxTranscriptTurns, "snapshot: transcript 上限")
    t.expectEqual(bigSnap.transcript.last?.id, "n\(PhoneRemote.maxTranscriptTurns + 9)",
                  "snapshot: 保留的是最近的 turn")

    // JSON 编解码 round-trip
    let data = PhoneRemote.stateJSON(snap)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    guard let decoded = try? decoder.decode(PhoneRemote.StateSnapshot.self, from: data) else {
        t.expect(false, "snapshot: JSON 可解码"); return
    }
    t.expectEqual(decoded, snap, "snapshot: JSON round-trip 相等")
}

// MARK: - H5 页面

func runPhoneRemotePage(_ t: TestRunner) {
    let token = PhoneRemote.makeToken()
    let html = PhoneRemote.pageHTML(token: token)
    t.expect(html.contains(token), "page: 内嵌 token")
    t.expect(html.contains("/api/state"), "page: state 端点")
    t.expect(html.contains("/api/send"), "page: send 端点")
    t.expect(html.contains("/api/select"), "page: select 端点")
    t.expect(html.contains("viewport-fit=cover"), "page: 移动端 viewport")
    t.expect(html.contains("lang=\"zh-CN\""), "page: 中文页面")
    t.expect(html.hasPrefix("<!DOCTYPE html>"), "page: DOCTYPE 开头")
    // 无外链资源 — 断网/隔离局域网也必须能加载
    t.expect(!html.contains("<script src="), "page: 无外部 script")
    t.expect(!html.lowercased().contains("<link "), "page: 无外部 stylesheet")
    t.expect(!html.contains("https://"), "page: 无外网引用")
}
