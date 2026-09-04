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
    // v0.5.20 项目切换路由
    if case .success(.project(let pid)) = route("POST", "/r/\(token)/api/project", #"{"projectId":"p1"}"#) {
        t.expectEqual(pid, "p1", "route: project 携带 projectId")
    } else {
        t.expect(false, "route: POST api/project → project")
    }
    if case .failure(.badRequest) = route("GET", "/r/\(token)/api/project") {} else {
        t.expect(false, "route: GET api/project → badRequest")
    }
    if case .success(.newSession(let npid)) = route("POST", "/r/\(token)/api/new", #"{"projectId":"p2"}"#) {
        t.expectEqual(npid, "p2", "route: new 携带 projectId")
    } else {
        t.expect(false, "route: POST api/new → newSession")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/api/new", "{}") {} else {
        t.expect(false, "route: 缺 projectId 的 new → badRequest")
    }
    // v0.5.25 附件上传路由
    if case .success(.attach(let n, let d)) =
        route("POST", "/r/\(token)/api/attach", #"{"name":"p.png","data":"aGVsbG8="}"#) {
        t.expectEqual(n, "p.png", "route: attach 携带文件名")
        t.expectEqual(d, "aGVsbG8=", "route: attach 携带 base64 数据")
    } else {
        t.expect(false, "route: POST api/attach → attach")
    }
    for bad in [#"{"name":"p.png"}"#, #"{"data":"aGk="}"#, "{}"] {
        if case .failure(.badRequest) = route("POST", "/r/\(token)/api/attach", bad) {} else {
            t.expect(false, "route: 缺字段 attach → badRequest (\(bad))")
        }
    }
    if case .failure(.badRequest) = route("GET", "/r/\(token)/api/attach") {} else {
        t.expect(false, "route: GET api/attach → badRequest")
    }
    // v0.5.27 图片服务路由
    if case .success(.turnImage(let tid, let idx)) = route("GET", "/r/\(token)/img/turn-abc/2") {
        t.expectEqual(tid, "turn-abc", "route: img 携带 turnId")
        t.expectEqual(idx, 2, "route: img 携带序号")
    } else {
        t.expect(false, "route: GET img/<turnId>/<i> → turnImage")
    }
    if case .failure(.badRequest) = route("GET", "/r/\(token)/img/turn-abc/x") {} else {
        t.expect(false, "route: img 非数字序号 → badRequest")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/img/turn-abc/0") {} else {
        t.expect(false, "route: POST img → badRequest")
    }
    if case .success(.pendingImage(let pidx)) = route("GET", "/r/\(token)/pending/0") {
        t.expectEqual(pidx, 0, "route: pending 序号")
    } else {
        t.expect(false, "route: GET pending/<i> → pendingImage")
    }
    if case .failure(.badRequest) = route("POST", "/r/\(token)/pending/0") {} else {
        t.expect(false, "route: POST pending → badRequest")
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
             status: .completed, startedAt: now,
             userImagePaths: ["/tmp/attachments/th1/t1/image-a.png"]),
        Turn(id: "t2", userInput: longText,
             items: [.assistantMessage(id: "m2", text: "好的")],
             status: .running, startedAt: now),
    ]
    let active = Thread(id: "th1", title: "修复构建", createdAt: now, updatedAt: now,
                        projectId: "pA", turns: turns)
    let other = Thread(id: "th2", title: "另一个会话",
                       createdAt: now, updatedAt: now.addingTimeInterval(-600), turns: [])

    let snap = PhoneRemote.buildState(threads: [other, active],
                                      activeId: "th1",
                                      rev: 7,
                                      hostname: "Chenlaiyi",
                                      appVersion: "0.5.19",
                                      projects: [
                                        PhoneRemote.ProjectSeed(id: "pB", name: "B项目",
                                                                path: "/tmp/b",
                                                                lastActivityAt: now.addingTimeInterval(-100)),
                                        PhoneRemote.ProjectSeed(id: "pA", name: "A项目",
                                                                path: "/tmp/a",
                                                                lastActivityAt: now.addingTimeInterval(-50)),
                                      ],
                                      activeProjectId: "pA",
                                      model: "MiniMax-M3",
                                      attachedCount: 2,
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

    // v0.5.20 项目维度: 会话归属 + 项目按最近活跃排序 + 计数
    t.expectEqual(snap.threads.first?.projectId, "pA", "snapshot: 会话携带 projectId")
    t.expectEqual(snap.threads.last?.projectId, nil, "snapshot: 未分类会话 projectId 为空")
    t.expectEqual(snap.projects.count, 2, "snapshot: 项目数")
    t.expectEqual(snap.projects.first?.id, "pA", "snapshot: 项目按最近活跃排前 (th1 更新于 now)")
    t.expectEqual(snap.projects.last?.id, "pB", "snapshot: 冷项目排后")
    t.expectEqual(snap.projects.first?.threadCount, 1, "snapshot: 项目会话计数")
    t.expectEqual(snap.projects.first?.name, "A项目", "snapshot: 项目名透传")
    t.expectEqual(snap.activeProjectId, "pA", "snapshot: activeProjectId 透传")
    t.expectEqual(snap.model, "MiniMax-M3", "snapshot: model 透传")
    t.expectEqual(snap.attachedCount, 2, "snapshot: attachedCount 透传")

    // transcript: app-progress 剔除 + 截断 + running 标记
    t.expectEqual(snap.transcript.count, 2, "snapshot: transcript 条数")
    t.expectEqual(snap.transcript[0].assistant, "已修复。", "snapshot: app-progress- 前缀剔除")
    t.expectEqual(snap.transcript[0].userImageCount, 1, "snapshot: 会话图片计数")
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

// MARK: - Markdown 输出渲染 (v0.5.23)

func runPhoneRemoteMarkdown(_ t: TestRunner) {
    // XSS: 原文 HTML 一律转义, 标签只由渲染器产出
    let xss = PhoneRemote.markdownHTML("<script>alert(1)</script>")
    t.expect(!xss.contains("<script"), "md: 原文 script 标签不出现")
    t.expect(xss.contains("&lt;script&gt;"), "md: 原文 script 已转义")

    // 行内: 加粗 / 行内代码 / 删除线 / 链接
    let inline = PhoneRemote.markdownHTML("这是 **加粗** 和 `代码` 与 ~~删掉~~ 的 [文档](https://a.b/c)。")
    t.expect(inline.contains("<strong>加粗</strong>"), "md: 加粗")
    t.expect(inline.contains("<code>代码</code>"), "md: 行内代码")
    t.expect(inline.contains("<del>删掉</del>"), "md: 删除线")
    t.expect(inline.contains("<a href=\"https://a.b/c\""), "md: 链接可点")

    // 危险 scheme 降级为纯文本
    let evil = PhoneRemote.markdownHTML("[点我](javascript:alert(1))")
    t.expect(!evil.contains("<a href=\"javascript:"), "md: javascript: 链接降级纯文本")

    // 标题层级: # → h3, ### → h4
    let heads = PhoneRemote.markdownHTML("# 大标题\n### 小标题")
    t.expect(heads.contains("<h3>大标题</h3>"), "md: 一级标题 → h3")
    t.expect(heads.contains("<h4>小标题</h4>"), "md: 三级标题 → h4")

    // 列表 / 任务清单 (混排列表需空行分隔)
    let list = PhoneRemote.markdownHTML("- 甲\n- 乙\n\n1. 一\n2. 二")
    t.expect(list.contains("<ul>"), "md: 无序列表")
    t.expect(list.contains("<li>甲</li>"), "md: 列表项")
    t.expect(list.contains("<ol>"), "md: 有序列表")
    let tasks = PhoneRemote.markdownHTML("- [x] 已装\n- [ ] 未装")
    t.expect(tasks.contains("☑") && tasks.contains("☐"), "md: 任务清单勾选态")

    // 代码块: fenced + 语言标签 + 内部转义
    let code = PhoneRemote.markdownHTML("```swift\nlet x = \"<b>\"\n```")
    t.expect(code.contains("codeBlock"), "md: 代码块容器")
    t.expect(code.contains("codeLang") && code.contains("swift"), "md: 语言标签")
    t.expect(code.contains("let x = \"&lt;b&gt;\""), "md: 代码内部转义")

    // 表格
    let table = PhoneRemote.markdownHTML("| 列A | 列B |\n| --- | --- |\n| 1 | 2 |")
    t.expect(table.contains("<table>") && table.contains("<th>列A</th>"), "md: 表格")

    // 引用 + 分隔线
    let misc = PhoneRemote.markdownHTML("> 引用一句\n\n---")
    t.expect(misc.contains("<blockquote>") && misc.contains("引用一句"), "md: 引用块")
    t.expect(misc.contains("<hr>"), "md: 分隔线")

    // 快照: assistantHTML 与 markdownHTML(assistant) 一致且非空
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let turn = Turn(id: "t1", userInput: "u",
                    items: [.assistantMessage(id: "m1", text: "# 标\n**粗**")],
                    status: .completed, startedAt: now)
    let th = Thread(id: "th", title: "t", createdAt: now, updatedAt: now, turns: [turn])
    let snap = PhoneRemote.buildState(threads: [th], activeId: "th", rev: 0,
                                      hostname: "h", appVersion: "v", now: now)
    t.expect(snap.transcript[0].assistantHTML.contains("<h3>标</h3>"), "md: 快照带渲染 HTML")
    t.expectEqual(snap.transcript[0].assistantHTML,
                  PhoneRemote.markdownHTML(snap.transcript[0].assistant),
                  "md: assistantHTML 与原文渲染一致")
}

// MARK: - 接入模式与公网中继 (v0.5.17/20)

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

    // H5 页面拆为骨架 + 静态资源；v0.5.96 全面重构 app.css 的移动端布局。
    // pageHTML() 只剩 32 行模板 + token + version 占位符 + 引导加载脚本。
    // 业务 JS / CSS / UI 元素全部搬到 Resources/PhoneRemote/{app.js,app.css}。

    // 1. 骨架断言
    t.expect(html.contains(token), "page: 内嵌 token")
    // v0.5.84: HTML 模板把 __TAPGO_WEB_VERSION__ 替换成 webClientVersion,
    // HTML 字面不应再含占位符, 取而代之以引导脚本里的 ?v= 参数引用 .version
    t.expect(!html.contains("__TAPGO_WEB_VERSION__"),
             "page: web 版本占位符已替换")
    t.expect(html.contains("?v=" + String(PhoneRemote.webClientVersion)) ||
             html.contains("?v=\""),
             "page: 资源 URL 带版本参数")
    t.expect(html.contains("viewport-fit=cover"), "page: 移动端 viewport")
    t.expect(html.contains("lang=\"zh-CN\""), "page: 中文页面")
    t.expect(html.hasPrefix("<!DOCTYPE html>"), "page: DOCTYPE 开头")
    t.expect(!html.contains("<script src="), "page: 无硬编码外部 script")
    t.expect(!html.lowercased().contains("<link "), "page: 无硬编码外部 stylesheet")
    t.expect(!html.contains("https://"), "page: 无外网引用")

    // 2. 引导脚本必须指向 /assets/app.css 与 app.js?v=<version>
    t.expect(html.contains("assets/app.css"), "page: 引导加载 app.css")
    t.expect(html.contains("assets/app.js"), "page: 引导加载 app.js")
    t.expect(html.contains("?v="), "page: 资源带版本号防缓存")

    // 3. BASE 自适应根路径: 公网中继 /remote/<machine>/r/<token>/ 下,
    // fetch 走 root + "r/" + TOKEN + ... 拼接, 不用绝对路径 /r/*。
    t.expect(html.contains("location.pathname.endsWith(\"/\")"), "page: BASE 自适应根路径")
    t.expect(!html.contains("fetch(\"/r/\""), "page: 不允许绝对路径 fetch")

    // 4. 引导首屏失败诊断
    t.expect(html.contains("正在连接") || html.contains("正在加载") || html.contains("连接"),
             "page: 首屏有可读诊断文案")

    // 5. webAsset(named:) 资源加载
    if let css = PhoneRemote.webAsset(named: "app.css") {
        t.expect(css.name == "app.css", "webAsset: app.css 名字")
        t.expect(css.contentType.hasPrefix("text/css"), "webAsset: app.css content-type = text/css")
        t.expect(css.data.count > 100, "webAsset: app.css 非空 (" + String(css.data.count) + " 字节)")
    } else {
        t.expect(false, "webAsset: app.css 应能加载")
    }
    if let js = PhoneRemote.webAsset(named: "app.js") {
        t.expect(js.name == "app.js", "webAsset: app.js 名字")
        t.expect(js.contentType.hasPrefix("text/javascript") || js.contentType.hasPrefix("application/javascript"),
                 "webAsset: app.js content-type = JS")
        t.expect(js.data.count > 100, "webAsset: app.js 非空 (" + String(js.data.count) + " 字节)")
    } else {
        t.expect(false, "webAsset: app.js 应能加载")
    }
    if let icon = PhoneRemote.webAsset(named: "app-icon.png") {
        t.expect(icon.contentType == "image/png", "webAsset: app-icon.png content-type = image/png")
        t.expect(icon.data.count > 100, "webAsset: app-icon.png 非空 (" + String(icon.data.count) + " 字节)")
    } else {
        t.expect(false, "webAsset: app-icon.png 应能加载")
    }
    t.expect(PhoneRemote.webAsset(named: "evil.js") == nil, "webAsset: 拒绝未知资源")
    t.expect(PhoneRemote.webAsset(named: "../etc/passwd") == nil, "webAsset: 拒绝路径穿越")

    // 6. webAssetResponse 返回正确 HTTP 响应
    let cssResp = String(decoding: PhoneRemote.webAssetResponse(named: "app.css"), as: UTF8.self)
    t.expect(cssResp.hasPrefix("HTTP/1.1 200 OK"), "webAssetResp: 200 状态行")
    t.expect(cssResp.contains("Content-Type: text/css"), "webAssetResp: Content-Type = text/css")
    t.expect(cssResp.contains("immutable"), "webAssetResp: 不可变缓存")
    t.expect(cssResp.contains("X-Content-Type-Options: nosniff"), "webAssetResp: 防嗅探")
    let notFound = String(decoding: PhoneRemote.webAssetResponse(named: "nope.js"), as: UTF8.self)
    t.expect(notFound.hasPrefix("HTTP/1.1 404"), "webAssetResp: 未知资源 -> 404")

    // 7. Route.asset 路由解析
    if case .success(.asset(let name)) = PhoneRemote.route(
        method: "GET",
        path: "/r/" + token + "/assets/app.js",
        body: Data(),
        expectedToken: token
    ) {
        t.expect(name == "app.js", "route: GET /r/<t>/assets/app.js -> .asset(app.js)")
    } else {
        t.expect(false, "route: GET /r/<t>/assets/app.js -> .asset")
    }
    if case .failure(.notFound) = PhoneRemote.route(
        method: "GET",
        path: "/r/" + token + "/assets/evil.js",
        body: Data(),
        expectedToken: token
    ) {
        t.expect(true, "route: 未知 asset -> notFound")
    } else {
        t.expect(false, "route: 未知 asset 应 notFound")
    }
    // POST /assets 路由层返回 notFound (资源路由只接 GET/HEAD),
    // 不是 badRequest。两者都能拒绝非法方法, 这里只确认拒绝即可。
    if case .failure(let err) = PhoneRemote.route(
        method: "POST",
        path: "/r/" + token + "/assets/app.js",
        body: Data(),
        expectedToken: token
    ) {
        t.expect(err == .notFound || err == .badRequest,
                 "route: POST /assets 拒绝 (got \(err))")
    } else {
        t.expect(false, "route: POST /assets 应拒绝")
    }

    // 8. app.js 必须含核心 API 路径
    if let jsAsset = PhoneRemote.webAsset(named: "app.js"),
       let jsStr = String(data: jsAsset.data, encoding: .utf8) {
        // app.js 用 `control(endpoint, body)` 包装 + `request("api/ctrl/" + endpoint)`,
        // 所以字面只含 "api/ctrl/" 拼接串; 端点名以参数传递, 不会单独出现字面。
        for marker in ["api/state", "api/send", "api/select", "api/new", "api/attach",
                       "api/ctrl/", "img/", "pending/"] {
            t.expect(jsStr.contains(marker), "app.js: 含 " + marker)
        }
        // 电脑控制端点必须作为字符串字面出现 (供 setInterval / 错误处理用)
        for endpoint in ["click", "type", "scroll", "key", "cmd", "screen"] {
            t.expect(jsStr.contains("\"" + endpoint + "\""),
                     "app.js: 端点字面 \"" + endpoint + "\"")
        }
        // app.js 必须含核心 UI class, 这是 v0.5.84 拆资源后页面仍能渲染的底线
        for cls in ["composer", "sidebar", "mobile-home", "busy-spinner", "modelSheet", "fileInput"] {
            t.expect(jsStr.contains(cls), "app.js: 含 class " + cls)
        }
        t.expect(jsStr.contains("当前设备上的工作区和任务"), "app.js: ZCode 式工作区总览标题")
        t.expect(jsStr.contains("data-action=\"collapse-all\"") && jsStr.contains("data-action=\"sort\""),
                 "app.js: 工作区折叠与排序动作")
        t.expect(jsStr.contains("chat-kicker\">任务会话"), "app.js: 双层任务会话导航")
        t.expect(jsStr.contains("organizeBy: \"workspace\""), "app.js: 清理旧时间视图偏好并固定工作区层级")
    } else {
        t.expect(false, "app.js 资源读取失败")
    }

    // 9. 当前 app.css 必须非空且含 :root + 关键变量及移动端首页约束
    if let cssAsset = PhoneRemote.webAsset(named: "app.css"),
       let cssStr = String(data: cssAsset.data, encoding: .utf8) {
        t.expect(cssStr.contains(":root"), "app.css: 含 :root 变量")
        t.expect(cssStr.contains("--background") || cssStr.contains("--brand"),
                 "app.css: 含主题色变量")
        t.expect(cssStr.contains("data-mobile-view=\"home\"") && cssStr.contains("composer-dock"),
                 "app.css: 首页强制隐藏输入器")
    } else {
        t.expect(false, "app.css 资源读取失败")
    }

    // 10. linkVersion 升级到 3
    t.expectEqual(PhoneRemote.linkVersion, 3, "page: linkVersion = 3")
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

    // 不传 control -> 键缺失 (与旧页面/旧 App 兼容)
    let legacy = PhoneRemote.buildState(threads: [], activeId: nil, rev: 0,
                                        hostname: "h", appVersion: "v", now: now)
    t.expect(legacy.control == nil, "snapshot: 缺省 control 为 nil")
    t.expect(!String(decoding: PhoneRemote.stateJSON(legacy), as: UTF8.self).contains("\"control\""),
             "snapshot: 旧快照 JSON 无 control 键")

    // 控制响应形态
    let err = String(decoding: PhoneRemote.controlErrorResponse("controlDisabled"), as: UTF8.self)
    t.expect(err.hasPrefix("HTTP/1.1 403"), "ctrl-resp: 关闭/无权限 -> 403")
    t.expect(err.contains(#"{"ok":false,"error":"controlDisabled"}"#), "ctrl-resp: error 码可机读")
    t.expect(String(decoding: PhoneRemote.controlOKResponse, as: UTF8.self)
        .hasPrefix("HTTP/1.1 200"), "ctrl-resp: 成功 -> 200 ok")

    // H5 页面 + app.js 含电脑控制入口与端点 (端点 URL 由 JS 拼接, 断言调用串本身)
    let html = PhoneRemote.pageHTML(token: PhoneRemote.makeToken())
    // v0.5.84 起 H5 拆资源, 电脑控制入口已在 index.html + app.js 中
    t.expect(html.contains("assets/app.css"), "page: 资源引导 app.css")
    t.expect(html.contains("assets/app.js"), "page: 资源引导 app.js")
    let jsSrc: String = PhoneRemote.webAsset(named: "app.js").flatMap {
        String(data: $0.data, encoding: .utf8)
    } ?? ""
    let cssSrc: String = PhoneRemote.webAsset(named: "app.css").flatMap {
        String(data: $0.data, encoding: .utf8)
    } ?? ""
    let endpoint = "screen"
    for marker in ["api/ctrl/" + endpoint,
                   "api/ctrl/screen",
                   "control(\"click\", { x, y, double",
                   "control(\"scroll\"",
                   "control(\"type\", { text }",
                   "control(\"key\", { key",
                   "control(\"cmd\", { action",
                   "\"lock\"", "\"sleep\"",
                   "data-action=\"control\"",
                   "data-key=\"return\"",
                   "电脑操作", "双击模式", "playPause"] {
        let inJS = jsSrc.contains(marker)
        let inCSS = cssSrc.contains(marker)
        let inHTML = html.contains(marker)
        t.expect(inJS || inCSS || inHTML, "page 含 " + marker + " (inJS=" + String(inJS) + " inCSS=" + String(inCSS) + " inHTML=" + String(inHTML) + ")")
    }
}
