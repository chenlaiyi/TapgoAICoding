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
    // 整秒基准: JSON 编码用 millisecondsSince1970, 带亚秒的 Date 会截断
    // 导致 round-trip 不等; 整秒值则无损。
    let now = Date(timeIntervalSince1970: 1_788_000_000)
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

// MARK: - 接入模式与公网中继 (v0.5.17)

func runPhoneRemoteAccessModes(_ t: TestRunner) {
    // 主机名 → 中继预设映射 (与服务器 nginx tapgo-remote.conf 一一对应)
    let chen = PhoneRemote.relayPreset(forLocalHostName: "Chenlaiyi")
    t.expect(chen != nil, "relay: Chenlaiyi 有预设")
    t.expectEqual(chen?.serverForwardPort ?? 0, 18723, "relay: chenlaiyi → 18723")
    t.expectEqual(chen?.pathPrefix ?? "", "/remote/chenlaiyi/", "relay: chenlaiyi 前缀")
    let jk = PhoneRemote.relayPreset(forLocalHostName: "JKMac-mini")
    t.expectEqual(jk?.serverForwardPort ?? 0, 18724, "relay: JKMac-mini → 18724")
    t.expectEqual(jk?.pathPrefix ?? "", "/remote/jk/", "relay: jk 前缀")
    let fafa = PhoneRemote.relayPreset(forLocalHostName: "fafadeMac-mini")
    t.expectEqual(fafa?.serverForwardPort ?? 0, 18725, "relay: fafadeMac-mini → 18725")
    t.expectEqual(fafa?.pathPrefix ?? "", "/remote/fafa/", "relay: fafa 前缀")
    t.expect(PhoneRemote.relayPreset(forLocalHostName: "unknown-machine") == nil,
             "relay: 未登记主机名返回 nil")

    // 多来源候选: fafa 机的 ComputerName 是本地化的 "发发的Mac mini",
    // 不含机器代号, 必须靠 LocalHostName/DNS 名兜底 (v0.5.17 真机回归)。
    let fafaMulti = PhoneRemote.relayPreset(hostCandidates: [
        "发发的Mac mini", "fafadeMac-mini", "fafadeMac-mini.local",
    ])
    t.expectEqual(fafaMulti?.serverForwardPort ?? 0, 18725,
                  "relay: 本地化 ComputerName 时由 LocalHostName 兜底")
    let chenMulti = PhoneRemote.relayPreset(hostCandidates: ["Chenlaiyi", "Chenlaiyi.local"])
    t.expectEqual(chenMulti?.serverForwardPort ?? 0, 18723, "relay: 多候选正常机")
    t.expect(PhoneRemote.relayPreset(hostCandidates: []) == nil, "relay: 空候选返回 nil")
    t.expect(PhoneRemote.relayPreset(hostCandidates: ["未知机器"]) == nil,
             "relay: 全未登记候选返回 nil")

    // 三台机器端口与路径互不冲突
    if let c = chen, let j = jk, let f = fafa {
        t.expect(c.serverForwardPort != j.serverForwardPort
                    && j.serverForwardPort != f.serverForwardPort
                    && c.serverForwardPort != f.serverForwardPort,
                 "relay: 三台转发端口互不相同")
        t.expect(c.pathPrefix != j.pathPrefix && j.pathPrefix != f.pathPrefix,
                 "relay: 三台 URL 前缀互不相同")
    }

    // 公网链接格式
    guard let preset = chen else {
        t.expect(false, "relay: 预设存在"); return
    }
    let token = PhoneRemote.makeToken()
    let url = PhoneRemote.relayLinkURL(preset: preset, token: token)
    t.expectEqual(url?.absoluteString ?? "", "https://pay.itapgo.com/remote/chenlaiyi/r/\(token)",
                  "relay: 公网链接 = https 域名 + 前缀 + /r/<token>")
    t.expect(PhoneRemote.relayLinkURL(preset: preset, token: "bad") == nil,
             "relay: 非法 token 拒绝构建公网链接")

    // ssh 隧道参数
    let args = PhoneRemote.tunnelArguments(serverForwardPort: 18723, localPort: 8723)
    t.expect(args.contains("-N") && args.contains("-T"), "tunnel: 无终端无命令会话")
    t.expect(args.contains("BatchMode=yes"), "tunnel: 仅密钥认证")
    t.expect(args.contains("ExitOnForwardFailure=yes"), "tunnel: 转发失败即退出 (可被监督重启)")
    t.expect(args.contains("ServerAliveInterval=15"), "tunnel: 保活探测")
    if let idx = args.firstIndex(of: "-R"), idx + 1 < args.count {
        t.expectEqual(args[idx + 1], "127.0.0.1:18723:127.0.0.1:8723", "tunnel: -R 转发串")
    } else {
        t.expect(false, "tunnel: 存在 -R 参数")
    }
    t.expectEqual(args.last ?? "", PhoneRemote.relaySSHDestination, "tunnel: 目的地在末位")

    // 隧道进程特征串 (孤儿清理用): 必须与真实 ssh 命令行尾部逐字匹配
    t.expectEqual(PhoneRemote.tunnelProcessPattern(serverForwardPort: 18723, localPort: 8723),
                  "127.0.0.1:18723:127.0.0.1:8723 root@139.9.61.199",
                  "tunnel: 进程特征串格式")
    let joinedArgs = PhoneRemote.tunnelArguments(serverForwardPort: 18724, localPort: 8723)
        .joined(separator: " ")
    t.expect(joinedArgs.contains(PhoneRemote.tunnelProcessPattern(serverForwardPort: 18724, localPort: 8723)),
             "tunnel: 特征串能匹配真实 ssh 命令行")

    // 服务器端僵尸转发清理参数
    let cleanArgs = PhoneRemote.remoteCleanupArguments(serverForwardPort: 18725)
    t.expect(!cleanArgs.contains("-N"), "cleanup: 不用 -N (需执行远端命令)")
    t.expectEqual(cleanArgs.last ?? "", "fuser -k -n tcp 18725 2>/dev/null; true",
                  "cleanup: 远端命令在末位且端口正确")
    t.expect(cleanArgs.contains("BatchMode=yes"), "cleanup: 仅密钥认证")

    // tailnet 地址判定 (100.64.0.0/10)
    t.expect(PhoneRemote.isTailnetIPv4("100.100.191.111"), "tailnet: 本机样例地址")
    t.expect(PhoneRemote.isTailnetIPv4("100.64.0.1"), "tailnet: 段首")
    t.expect(PhoneRemote.isTailnetIPv4("100.127.255.254"), "tailnet: 段尾")
    t.expect(!PhoneRemote.isTailnetIPv4("100.63.0.1"), "tailnet: 段前拒绝")
    t.expect(!PhoneRemote.isTailnetIPv4("100.128.0.1"), "tailnet: 段后拒绝")
    t.expect(!PhoneRemote.isTailnetIPv4("192.168.2.26"), "tailnet: 局域网地址拒绝")
    t.expect(!PhoneRemote.isTailnetIPv4("not-an-ip"), "tailnet: 非法输入拒绝")
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

// MARK: - 电脑控制: 路由解析 (v0.5.17)

func runPhoneRemoteControlRoutes(_ t: TestRunner) {
    let token = PhoneRemote.makeToken()
    func route(_ method: String, _ path: String, _ body: String = "",
               expected: String = token) -> Result<PhoneRemote.Route, PhoneRemote.RouteError> {
        PhoneRemote.route(method: method, path: path, body: Data(body.utf8), expectedToken: expected)
    }

    // screen: 只接受 GET
    if case .success(.controlScreen) = route("GET", "/r/\(token)/api/ctrl/screen") {} else {
        t.expect(false, "ctrl: GET screen → controlScreen")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/screen") {} else {
        t.expect(false, "ctrl: POST screen → badRequest")
    }

    // click: 归一化坐标 + 可选 double
    if case .success(.controlClick(let x, let y, let dbl)) =
        route("POST", "/r/\(token)/api/ctrl/click", #"{"x":0.25,"y":0.75,"double":true}"#) {
        t.expectEqual(x, 0.25, "ctrl: click x 解析")
        t.expectEqual(y, 0.75, "ctrl: click y 解析")
        t.expect(dbl, "ctrl: click double=true")
    } else {
        t.expect(false, "ctrl: click 完整 body → controlClick")
    }
    if case .success(.controlClick(_, _, let dbl)) =
        route("POST", "/r/\(token)/api/ctrl/click", #"{"x":0.5,"y":0.5}"#) {
        t.expect(!dbl, "ctrl: double 缺省 false")
    } else {
        t.expect(false, "ctrl: click 无 double 字段可用")
    }
    for bad in [#"{"y":0.5}"#, #"{"x":0.5}"#, #"{"x":1.5,"y":0.5}"#,
                #"{"x":-0.1,"y":0.5}"#, #"{"x":"a","y":0.5}"#, "not json"] {
        if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/click", bad) {} else {
            t.expect(false, "ctrl: 非法 click body 拒绝 (\(bad))")
        }
    }
    if case .success(.controlClick(0, 1, _)) =
        route("POST", "/r/\(token)/api/ctrl/click", #"{"x":0,"y":1}"#) {} else {
        t.expect(false, "ctrl: click 边界 (0,1) 合法")
    }

    // scroll
    if case .success(.controlScroll(let dy)) =
        route("POST", "/r/\(token)/api/ctrl/scroll", #"{"dy":-5}"#) {
        t.expectEqual(dy, -5, "ctrl: scroll dy 解析")
    } else {
        t.expect(false, "ctrl: scroll → controlScroll")
    }
    for bad in [#"{"dy":0}"#, "{}", #"{"dy":"up"}"#] {
        if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/scroll", bad) {} else {
            t.expect(false, "ctrl: 非法 scroll body 拒绝 (\(bad))")
        }
    }

    // type
    if case .success(.controlType(let text)) =
        route("POST", "/r/\(token)/api/ctrl/type", #"{"text":"打开终端"}"#) {
        t.expectEqual(text, "打开终端", "ctrl: type 携带 UTF-8 文本")
    } else {
        t.expect(false, "ctrl: type → controlType")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/type", #"{"text":""}"#) {} else {
        t.expect(false, "ctrl: 空 type 拒绝")
    }

    // key: 白名单枚举
    if case .success(.controlKey(let key)) =
        route("POST", "/r/\(token)/api/ctrl/key", #"{"key":"return"}"#) {
        t.expectEqual(key, .`return`, "ctrl: key return")
    } else {
        t.expect(false, "ctrl: key return → controlKey")
    }
    if case .success(.controlKey(let media)) =
        route("POST", "/r/\(token)/api/ctrl/key", #"{"key":"volumeUp"}"#) {
        t.expectEqual(media, .volumeUp, "ctrl: key volumeUp")
    } else {
        t.expect(false, "ctrl: key volumeUp → controlKey")
    }
    for bad in [#"{"key":"nope"}"#, #"{"key":"Return"}"#, "{}"] {
        if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/key", bad) {} else {
            t.expect(false, "ctrl: 未知 key 拒绝 (\(bad))")
        }
    }

    // cmd: lock / sleep
    if case .success(.controlCommand(let lock)) =
        route("POST", "/r/\(token)/api/ctrl/cmd", #"{"action":"lock"}"#) {
        t.expectEqual(lock, .lock, "ctrl: cmd lock")
    } else {
        t.expect(false, "ctrl: cmd lock → controlCommand")
    }
    if case .success(.controlCommand(let sleep)) =
        route("POST", "/r/\(token)/api/ctrl/cmd", #"{"action":"sleep"}"#) {
        t.expectEqual(sleep, .sleep, "ctrl: cmd sleep")
    } else {
        t.expect(false, "ctrl: cmd sleep → controlCommand")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/ctrl/cmd", #"{"action":"reboot"}"#) {} else {
        t.expect(false, "ctrl: 未登记 action 拒绝")
    }

    // 错误 token 一律 unauthorized (控制面同样受 token 保护)
    let stranger = PhoneRemote.makeToken()
    for (m, p, b) in [("GET", "/r/\(stranger)/api/ctrl/screen", ""),
                      ("POST", "/r/\(stranger)/api/ctrl/click", #"{"x":0.5,"y":0.5}"#),
                      ("POST", "/r/\(stranger)/api/ctrl/cmd", #"{"action":"lock"}"#)] {
        if case .failure(.unauthorized) = route(m, p, b, expected: token) {} else {
            t.expect(false, "ctrl: token 不符的 \(p) → unauthorized")
        }
    }
}

// MARK: - 电脑控制: 按键映射 (v0.5.17)

func runPhoneRemoteControlKeys(_ t: TestRunner) {
    // 普通键 → kVK_* 虚拟键码
    let normal: [(String, Int)] = [("return", 36), ("escape", 53), ("tab", 48), ("space", 49),
                                   ("delete", 51), ("forwardDelete", 117),
                                   ("left", 123), ("right", 124), ("down", 125), ("up", 126),
                                   ("home", 115), ("end", 119), ("pageUp", 116), ("pageDown", 121)]
    for (name, code) in normal {
        let key = PhoneRemote.ControlKey(rawValue: name)
        t.expectEqual(key?.virtualKeyCode, code, "key: \(name) → \(code)")
        t.expect(key?.mediaKeyType == nil, "key: \(name) 非媒体键")
    }
    // 媒体键 → NX_KEYTYPE_*
    let media: [(String, Int)] = [("volumeUp", 0), ("volumeDown", 1), ("brightnessUp", 2),
                                  ("brightnessDown", 3), ("mute", 7), ("playPause", 16)]
    for (name, type) in media {
        let key = PhoneRemote.ControlKey(rawValue: name)
        t.expectEqual(key?.mediaKeyType, type, "key: \(name) → NX \(type)")
        t.expect(key?.virtualKeyCode == nil, "key: \(name) 无普通键码")
    }
    // 全集: 二者必居其一且互斥; 解析大小写敏感
    t.expectEqual(PhoneRemote.ControlKey.allCases.count, 20, "key: 全集 20 个")
    for k in PhoneRemote.ControlKey.allCases {
        t.expect(k.virtualKeyCode != nil || k.mediaKeyType != nil, "key: \(k.rawValue) 可投递")
        t.expect(!(k.virtualKeyCode != nil && k.mediaKeyType != nil), "key: \(k.rawValue) 两类互斥")
    }
    t.expect(PhoneRemote.ControlKey(rawValue: "Return") == nil, "key: 大写开头拒绝")
    t.expect(PhoneRemote.ControlKey(rawValue: "") == nil, "key: 空串拒绝")

    // 系统命令白名单
    t.expect(PhoneRemote.ControlAction(rawValue: "lock") == .lock, "action: lock")
    t.expect(PhoneRemote.ControlAction(rawValue: "sleep") == .sleep, "action: sleep")
    t.expect(PhoneRemote.ControlAction(rawValue: "reboot") == nil, "action: reboot 未开放")
    t.expect(PhoneRemote.ControlAction(rawValue: "") == nil, "action: 空串拒绝")

    // JSON 数值/布尔字段解析助手
    t.expectEqual(PhoneRemote.jsonDoubleField(Data(#"{"dy":5}"#.utf8), "dy"), 5, "json: 整数按 Double 读")
    t.expectEqual(PhoneRemote.jsonDoubleField(Data(#"{"dy":-0.5}"#.utf8), "dy"), -0.5, "json: 小数读取")
    t.expect(PhoneRemote.jsonDoubleField(Data(#"{"dy":true}"#.utf8), "dy") == nil, "json: Bool 不算数值")
    t.expect(PhoneRemote.jsonDoubleField(Data("{}".utf8), "dy") == nil, "json: 缺字段返回 nil")
    t.expectEqual(PhoneRemote.jsonBoolField(Data(#"{"double":true}"#.utf8), "double"), true, "json: Bool 读取")
    t.expect(PhoneRemote.jsonBoolField(Data(#"{"double":1}"#.utf8), "double") == nil, "json: 数值不算 Bool")
}

// MARK: - 电脑控制: 快照 / 响应 / 页面 (v0.5.17)

func runPhoneRemoteControlSnapshot(_ t: TestRunner) {
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let ctrl = PhoneRemote.ControlStatus(enabled: true, screenAllowed: true,
                                         accessibilityAllowed: false)
    let snap = PhoneRemote.buildState(threads: [], activeId: nil, rev: 3,
                                      hostname: "h", appVersion: "0.5.17",
                                      control: ctrl, now: now)
    t.expectEqual(snap.control, ctrl, "snapshot: control 块透传")

    // JSON: 含 control 字段且可 round-trip
    let data = PhoneRemote.stateJSON(snap)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    guard let decoded = try? decoder.decode(PhoneRemote.StateSnapshot.self, from: data) else {
        t.expect(false, "snapshot: control JSON 可解码"); return
    }
    t.expectEqual(decoded.control, ctrl, "snapshot: control round-trip")
    let json = String(decoding: data, as: UTF8.self)
    t.expect(json.contains("\"accessibilityAllowed\":false"), "snapshot: JSON 含权限字段")

    // 不传 control → 键缺失 (与旧页面/旧 App 兼容)
    let legacy = PhoneRemote.buildState(threads: [], activeId: nil, rev: 0,
                                        hostname: "h", appVersion: "v", now: now)
    t.expect(legacy.control == nil, "snapshot: 缺省 control 为 nil")
    t.expect(!String(decoding: PhoneRemote.stateJSON(legacy), as: UTF8.self).contains("\"control\""),
             "snapshot: 旧快照 JSON 无 control 键")

    // 控制响应形态
    let err = String(decoding: PhoneRemote.controlErrorResponse("controlDisabled"), as: UTF8.self)
    t.expect(err.hasPrefix("HTTP/1.1 403"), "ctrl-resp: 关闭/无权限 → 403")
    t.expect(err.contains(#"{"ok":false,"error":"controlDisabled"}"#), "ctrl-resp: error 码可机读")
    t.expect(String(decoding: PhoneRemote.controlOKResponse, as: UTF8.self)
        .hasPrefix("HTTP/1.1 200"), "ctrl-resp: 成功 → 200 ok")

    // H5 页面含电脑控制入口与端点 (端点 URL 由 JS 拼接, 断言调用串本身)
    let html = PhoneRemote.pageHTML(token: PhoneRemote.makeToken())
    for marker in [#"/api/ctrl/" + endpoint"#,
                   #"api/ctrl/screen", { cache: "no-store" }"#,
                   #"ctrl("click", { x: x, y: y, double: dbl })"#,
                   #"ctrl("scroll", { dy: parseFloat(b.dataset.scroll) })"#,
                   #"ctrl("type", { text: v })"#,
                   #"ctrl("key", { key: b.dataset.key })"#,
                   #"ctrl("cmd", { action: "lock" })"#,
                   #"ctrl("cmd", { action: "sleep" })"#,
                   "tabCtrl", "shotBtn", "data-key=\"return\"", "data-scroll",
                   "电脑控制", "双击模式", "playPause"] {
        t.expect(html.contains(marker), "page: 含 \(marker)")
    }
}
