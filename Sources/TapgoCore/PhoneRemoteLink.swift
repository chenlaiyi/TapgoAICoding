import Foundation

/// 手机远程控制 (v2) — "扫码即开 H5" 形态。
///
/// v0.5.5/v0.5.6 的 `MobilePairing` 走 `tapgo-pair://` 自定义 scheme, 要求手机
/// 预装原生 iOS App。v0.5.16 起改为对标 ZCode 移动端远程控制的体验: Mac 端
/// 内置一个带 token 鉴权的 HTTP 服务, QR 里直接编码
/// `http://<局域网IP>:<端口>/r/<token>` —— iPhone 相机扫码立刻在 Safari 打开
/// H5 控制页, 无需安装任何 App。
///
/// 本文件只放协议层 (纯 Foundation, 不依赖 Network/UI), 方便单测覆盖:
/// token 生成与校验、链接与路由解析、极简 HTTP 报文解析/序列化、
/// 状态快照 JSON、H5 页面渲染。真实的 NWListener 装配在 App 层
/// `PhoneRemoteServer.swift`。
public enum PhoneRemote {

    /// 默认监听端口 (与 v1 配对协议共用历史端口段)。
    public static let defaultPort = 8723
    /// 端口被占用时向后扫描的范围。
    public static let portScanRange = 8723...8733
    /// 链接协议版本, 进 H5 页面与 /api/state 便于以后兼容判断。
    public static let linkVersion = 2

    /// transcript 最多回带最近多少个 turn (H5 端向下翻由 Mac 端后续版本支持)。
    public static let maxTranscriptTurns = 30
    /// 单段文本 (用户输入 / 助手回复) 截断长度, 防止超长会话撑爆轮询响应。
    public static let maxTextLength = 6000
    /// 会话列表最多回带多少个 (按 updatedAt 取最新)。
    public static let maxThreads = 50

    // MARK: - Token

    /// 生成 128-bit 随机 token 的 base64url 形式 (22 字符, 无 `=`/`+`/`/`)。
    /// token 就是这条链接的全部鉴权凭据, 泄露等同交出控制权, 因此允许用户
    /// 在 UI 里一键轮换。
    public static func makeToken() -> String {
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &rng) }
        return base64URL(bytes)
    }

    /// 校验 token 形态 (22 字符 base64url 字符集)。
    public static func isValidToken(_ s: String) -> Bool {
        guard s.count == 22 else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return s.allSatisfy { allowed.contains($0) }
    }

    private static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Link

    /// 构造手机端打开的链接: `http://<host>:<port>/r/<token>`。
    /// `host` 是 Mac 的局域网 IPv4; 域名形式 (`.local`) 部分 Android/旧
    /// Safari 解析慢, 统一走 IP。
    public static func linkURL(host: String, port: Int, token: String) -> URL? {
        guard isValidToken(token) else { return nil }
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.port = port
        comps.path = "/r/\(token)"
        return comps.url
    }

    // MARK: - Access modes (v0.5.17)

    /// 手机访问 Mac 的三种接入方式。三条路最终都落在同一个本地 HTTP 服务
    /// (`/r/<token>` 路由不变), 区别只在链接的 host 部分。
    public enum AccessMode: String, CaseIterable, Equatable {
        /// 同一 Wi-Fi 直连 `http://<局域网IP>:8723`。
        case lan
        /// Tailscale 虚拟网内 `http://<100.x IP>:8723` — 手机装 Tailscale
        /// 登同一 tailnet 后任意网络可达。
        case tailnet
        /// `https://pay.itapgo.com/remote/<machine>/r/<token>` — 经 TapgoServer
        /// 的 SSH 反向隧道 + nginx 加密中继, 任意网络可达, 无需装任何 App。
        case relay
    }

    /// 公网中继预设: 服务器上 sshd 转发端口 + nginx 前缀一一对应。
    /// 端口分配 18723-18725, 前缀与 nginx `extension/pay.itapgo.com/tapgo-remote.conf`
    /// 保持同步 (改动必须两侧同时进行)。
    public struct RelayPreset: Equatable {
        public let serverForwardPort: Int
        public let pathPrefix: String
        public let publicBase: String

        public init(serverForwardPort: Int, pathPrefix: String, publicBase: String) {
            self.serverForwardPort = serverForwardPort
            self.pathPrefix = pathPrefix
            self.publicBase = publicBase
        }
    }

    /// 隧道 SSH 目的地 (三台 Mac 的 ~/.ssh 均已配置 root 免密)。
    public static let relaySSHDestination = "root@139.9.61.199"

    /// 按单个主机名 (大小写不敏感包含匹配) 返回公网中继预设。
    public static func relayPreset(forLocalHostName name: String) -> RelayPreset? {
        let n = name.lowercased()
        if n.contains("fafa") {
            return RelayPreset(serverForwardPort: 18725, pathPrefix: "/remote/fafa/",
                               publicBase: "https://pay.itapgo.com")
        }
        if n.contains("jk") {
            return RelayPreset(serverForwardPort: 18724, pathPrefix: "/remote/jk/",
                               publicBase: "https://pay.itapgo.com")
        }
        if n.contains("chenlaiyi") {
            return RelayPreset(serverForwardPort: 18723, pathPrefix: "/remote/chenlaiyi/",
                               publicBase: "https://pay.itapgo.com")
        }
        return nil
    }

    /// 多来源主机名候选任一匹配即返回预设。Mac 的 ComputerName 可能是
    /// 完全本地化的名字 (如 "发发的Mac mini", 不含任何机器代号), 因此
    /// 必须同时尝试 LocalHostName / DNS 主机名等来源。
    public static func relayPreset(hostCandidates: [String]) -> RelayPreset? {
        for candidate in hostCandidates where !candidate.isEmpty {
            if let preset = relayPreset(forLocalHostName: candidate) { return preset }
        }
        return nil
    }

    /// 公网中继链接: `<publicBase><pathPrefix>r/<token>`。
    public static func relayLinkURL(preset: RelayPreset, token: String) -> URL? {
        guard isValidToken(token) else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = preset.publicBase.replacingOccurrences(of: "https://", with: "")
        comps.path = "\(preset.pathPrefix)r/\(token)"
        return comps.url
    }

    /// `ssh -R` 反向隧道参数 (不含 ssh 可执行文件本身)。纯函数方便单测。
    public static func tunnelArguments(serverForwardPort: Int, localPort: Int) -> [String] {
        [
            "-N", "-T",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-R", "127.0.0.1:\(serverForwardPort):127.0.0.1:\(localPort)",
            relaySSHDestination,
        ]
    }

    /// Tailscale CGNAT 段 (100.64.0.0/10) 判定 — utun 网卡上的 100.64-100.127
    /// 即 tailnet 地址。
    public static func isTailnetIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return false }
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }

    // MARK: - Routing

    /// 一条已鉴权(或明确拒绝)的请求意图。
    public enum Route: Equatable {
        /// GET /r/<token>(/) — H5 页面本体。
        case page
        /// GET /r/<token>/api/state — 全量状态快照 JSON。
        case state
        /// POST /r/<token>/api/send `{"text": "..."}` — 向当前会话发送指令。
        case send(text: String)
        /// POST /r/<token>/api/select `{"threadId": "..."}` — 切换活动会话。
        case select(threadId: String)
        // MARK: 电脑控制 (v0.5.17) — 坐标均为归一化 0...1 (相对主屏截图)。
        /// GET /r/<token>/api/ctrl/screen — 主屏截图 JPEG。
        case controlScreen
        /// POST /r/<token>/api/ctrl/click `{"x":0.5,"y":0.5,"double":false}`。
        case controlClick(x: Double, y: Double, double: Bool)
        /// POST /r/<token>/api/ctrl/scroll `{"dy": 5}` — 行数, 正数向下滚。
        case controlScroll(deltaY: Double)
        /// POST /r/<token>/api/ctrl/type `{"text": "..."}` — 当作键盘输入。
        case controlType(text: String)
        /// POST /r/<token>/api/ctrl/key `{"key": "return"}` — 单键/媒体键。
        case controlKey(key: ControlKey)
        /// POST /r/<token>/api/ctrl/cmd `{"action": "lock"}` — 系统级命令。
        case controlCommand(action: ControlAction)
    }

    /// 手机可控的命名按键 (v0.5.17)。普通键走 `kVK_*` 虚拟键码; 媒体键
    /// (音量/亮度/播放) 走 systemDefined 事件, 两者互斥。
    public enum ControlKey: String, CaseIterable, Equatable {
        case `return`, escape, tab, space, delete, forwardDelete
        case up, down, left, right, home, end, pageUp, pageDown
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, playPause

        /// 普通键的 macOS 虚拟键码 (kVK_*); 媒体键返回 nil。
        public var virtualKeyCode: Int? {
            switch self {
            case .return: return 36
            case .escape: return 53
            case .tab: return 48
            case .space: return 49
            case .delete: return 51
            case .forwardDelete: return 117
            case .up: return 126
            case .down: return 125
            case .left: return 123
            case .right: return 124
            case .home: return 115
            case .end: return 119
            case .pageUp: return 116
            case .pageDown: return 121
            default: return nil
            }
        }

        /// 媒体键的 NX_KEYTYPE_* 值 (ev_keymap.h); 普通键返回 nil。
        public var mediaKeyType: Int? {
            switch self {
            case .volumeUp: return 0
            case .volumeDown: return 1
            case .brightnessUp: return 2
            case .brightnessDown: return 3
            case .mute: return 7
            case .playPause: return 16
            default: return nil
            }
        }
    }

    /// 系统级控制命令 (v0.5.17)。
    public enum ControlAction: String, CaseIterable, Equatable {
        /// Ctrl+Cmd+Q 锁屏。
        case lock
        /// pmset sleepnow 睡眠。
        case sleep
    }

    public enum RouteError: Error, Equatable {
        /// 路径里的 token 与当前 token 不符。
        case unauthorized
        /// token 对但路径不存在。
        case notFound
        /// 路径对但方法/JSON body 不合法。
        case badRequest
    }

    /// 把已解析的 HTTP 请求映射为 Route。`expectedToken` 用于常量时间比对。
    public static func route(method: String,
                             path: String,
                             body: Data,
                             expectedToken: String) -> Result<Route, RouteError> {
        // /r/<token>[/...]
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0] == "r" else { return .failure(.notFound) }
        guard constantTimeEquals(parts[1], expectedToken) else { return .failure(.unauthorized) }
        let rest = Array(parts.dropFirst(2))
        switch rest {
        case [], [""]:
            guard method == "GET" || method == "HEAD" else { return .failure(.badRequest) }
            return .success(.page)
        case ["api", "state"]:
            guard method == "GET" else { return .failure(.badRequest) }
            return .success(.state)
        case ["api", "send"]:
            guard method == "POST", let text = jsonStringField(body, "text"), !text.isEmpty else {
                return .failure(.badRequest)
            }
            return .success(.send(text: text))
        case ["api", "select"]:
            guard method == "POST", let id = jsonStringField(body, "threadId"), !id.isEmpty else {
                return .failure(.badRequest)
            }
            return .success(.select(threadId: id))
        case ["api", "ctrl", "screen"]:
            guard method == "GET" else { return .failure(.badRequest) }
            return .success(.controlScreen)
        case ["api", "ctrl", "click"]:
            guard method == "POST",
                  let x = jsonDoubleField(body, "x"), x >= 0, x <= 1,
                  let y = jsonDoubleField(body, "y"), y >= 0, y <= 1
            else { return .failure(.badRequest) }
            return .success(.controlClick(x: x, y: y, double: jsonBoolField(body, "double") ?? false))
        case ["api", "ctrl", "scroll"]:
            guard method == "POST", let dy = jsonDoubleField(body, "dy"), dy != 0 else {
                return .failure(.badRequest)
            }
            return .success(.controlScroll(deltaY: dy))
        case ["api", "ctrl", "type"]:
            guard method == "POST", let text = jsonStringField(body, "text"), !text.isEmpty else {
                return .failure(.badRequest)
            }
            return .success(.controlType(text: text))
        case ["api", "ctrl", "key"]:
            guard method == "POST",
                  let raw = jsonStringField(body, "key"),
                  let key = ControlKey(rawValue: raw)
            else { return .failure(.badRequest) }
            return .success(.controlKey(key: key))
        case ["api", "ctrl", "cmd"]:
            guard method == "POST",
                  let raw = jsonStringField(body, "action"),
                  let action = ControlAction(rawValue: raw)
            else { return .failure(.badRequest) }
            return .success(.controlCommand(action: action))
        default:
            return .failure(.notFound)
        }
    }

    /// 常量时间字符串比对, 避免逐字节提前返回造成的 timing 侧信道。
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        var diff: Int = lhs.count ^ rhs.count
        for i in 0..<max(lhs.count, rhs.count) {
            diff |= Int((i < lhs.count ? lhs[i] : 0) ^ (i < rhs.count ? rhs[i] : 0))
        }
        return diff == 0
    }

    /// 从 `{"key": "value"}` 形态的小 JSON body 里取一个字符串字段。
    private static func jsonStringField(_ data: Data, _ key: String) -> String? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj[key] as? String
        else { return nil }
        return value
    }

    /// 从 JSON body 里取一个数值字段 (Int/Double 都接受)。JSONSerialization
    /// 在 Darwin 上把 true/false 也解析成 NSNumber, 这里用 CFBooleanGetTypeID
    /// 把真 Bool 排除掉, 避免 `{"dy":true}` 被当成数值 1。
    static func jsonDoubleField(_ data: Data, _ key: String) -> Double? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = obj[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    /// 从 JSON body 里取一个 Bool 字段 (数值不算 Bool)。
    static func jsonBoolField(_ data: Data, _ key: String) -> Bool? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = obj[key] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return nil }
        return number.boolValue
    }

    // MARK: - Minimal HTTP

    /// 解析出的请求 (仅服务端需要的字段)。
    public struct ParsedRequest: Equatable {
        public let method: String
        /// 不含 query 的 path。
        public let path: String
        public let body: Data
    }

    /// 请求头最大字节数; 超过视为恶意/损坏, 直接断开。
    public static let maxHeadBytes = 16_384
    /// 请求 body 最大字节数。
    public static let maxBodyBytes = 65_536

    /// 从字节流里解析一条完整 HTTP/1.1 请求。
    /// 返回 nil 表示数据还没到齐 (调用方继续收); 数据明显超限也返回 nil,
    /// 由调用方靠 `isRequestOversized` 判断并断开。
    public static func parseRequest(_ data: Data) -> ParsedRequest? {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let head = String(data: data.subdata(in: data.startIndex..<headEnd.lowerBound), encoding: .utf8) ?? ""
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let reqParts = requestLine.split(separator: " ")
        guard reqParts.count >= 2 else { return nil }
        let method = String(reqParts[0]).uppercased()
        let target = String(reqParts[1])
        // 去掉 query string
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target

        var contentLength = 0
        for line in lines {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard contentLength >= 0, contentLength <= maxBodyBytes else { return nil }

        let headRange = headEnd.upperBound..<data.endIndex
        let available = data.distance(from: headRange.lowerBound, to: headRange.upperBound)
        guard available >= contentLength else { return nil }
        let bodyStart = data.index(headRange.lowerBound, offsetBy: 0)
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        return ParsedRequest(method: method, path: path, body: body)
    }

    /// 数据是否已经明显超出合法请求尺寸 (用于决定直接断开而不是继续等)。
    public static func isRequestOversized(_ buffer: Data) -> Bool {
        buffer.count > maxHeadBytes + maxBodyBytes
    }

    /// 序列化一个 HTTP/1.1 响应 (固定 `Connection: close`, 服务端不维护
    /// keep-alive 状态机, H5 每 2s 轮询一条新连接足够快)。
    public static func httpResponse(status: Int,
                                    reason: String,
                                    contentType: String,
                                    body: Data) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    public static func jsonOK(_ body: Data) -> Data {
        httpResponse(status: 200, reason: "OK", contentType: "application/json; charset=utf-8", body: body)
    }

    public static var forbiddenResponse: Data {
        httpResponse(status: 403, reason: "Forbidden", contentType: "text/plain; charset=utf-8",
                     body: Data("forbidden\n".utf8))
    }

    public static var notFoundResponse: Data {
        httpResponse(status: 404, reason: "Not Found", contentType: "text/plain; charset=utf-8",
                     body: Data("not found\n".utf8))
    }

    public static var badRequestResponse: Data {
        httpResponse(status: 400, reason: "Bad Request", contentType: "text/plain; charset=utf-8",
                     body: Data("bad request\n".utf8))
    }

    /// 控制类请求被拒 (开关关闭 / 权限缺失) 时的 JSON 响应; H5 靠 `error`
    /// 字段区分提示语。403 而不是 200, 与鉴权失败同一语义层。
    public static func controlErrorResponse(_ code: String) -> Data {
        let body = #"{"ok":false,"error":"\#(code)"}"#
        return httpResponse(status: 403, reason: "Forbidden",
                            contentType: "application/json; charset=utf-8",
                            body: Data(body.utf8))
    }

    /// 控制动作成功的 JSON 响应。
    public static var controlOKResponse: Data {
        httpResponse(status: 200, reason: "OK",
                     contentType: "application/json; charset=utf-8",
                     body: Data(#"{"ok":true}"#.utf8))
    }

    // MARK: - State snapshot

    public struct ThreadInfo: Codable, Equatable {
        public var id: String
        public var title: String
        public var updatedAt: Date
        public var turnCount: Int
        /// 最近一个 turn 正在运行或等待确认。
        public var busy: Bool
    }

    public struct TranscriptTurn: Codable, Equatable {
        public var id: String
        public var user: String
        public var status: String
        public var assistant: String
        /// 该 turn 是否触发了命令/文件变更 (H5 上显示 "正在执行" 徽标)。
        public var running: Bool
    }

    public struct ControlStatus: Codable, Equatable {
        /// Mac 端是否允许手机控制电脑 (UI 开关)。
        public var enabled: Bool
        /// 本 App 是否已获「屏幕录制」权限 (截屏)。
        public var screenAllowed: Bool
        /// 本 App 是否已获「辅助功能」权限 (鼠标/键盘/系统命令)。
        public var accessibilityAllowed: Bool

        public init(enabled: Bool, screenAllowed: Bool, accessibilityAllowed: Bool) {
            self.enabled = enabled
            self.screenAllowed = screenAllowed
            self.accessibilityAllowed = accessibilityAllowed
        }
    }

    public struct StateSnapshot: Codable, Equatable {
        public var rev: Int
        public var hostname: String
        public var appVersion: String
        public var linkVersion: Int
        public var activeId: String?
        public var threads: [ThreadInfo]
        public var transcript: [TranscriptTurn]
        /// 电脑控制可用性; nil 时 H5 隐藏电脑控制入口。
        public var control: ControlStatus?
    }

    /// 从 SessionStore 的数据构建 H5 需要的全量快照。纯函数, 方便单测。
    public static func buildState(threads: [Thread],
                                  activeId: String?,
                                  rev: Int,
                                  hostname: String,
                                  appVersion: String,
                                  control: ControlStatus? = nil,
                                  now: Date = Date()) -> StateSnapshot {
        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxThreads)
        let infos = sorted.map { t -> ThreadInfo in
            ThreadInfo(id: t.id,
                       title: truncate(t.title.isEmpty ? "未命名会话" : t.title),
                       updatedAt: t.updatedAt,
                       turnCount: t.turns.count,
                       busy: t.turns.last.map { $0.status == .running || $0.status == .awaitingApproval } ?? false)
        }
        var transcript: [TranscriptTurn] = []
        if let active = threads.first(where: { $0.id == activeId }) ?? threads.first {
            transcript = active.turns.suffix(maxTranscriptTurns).map { turn in
                TranscriptTurn(id: turn.id,
                               user: truncate(userText(turn)),
                               status: turn.status.rawValue,
                               assistant: truncate(assistantText(turn)),
                               running: turn.status == .running || turn.status == .awaitingApproval)
            }
        }
        return StateSnapshot(rev: rev,
                             hostname: hostname,
                             appVersion: appVersion,
                             linkVersion: PhoneRemote.linkVersion,
                             activeId: activeId ?? threads.first?.id,
                             threads: Array(infos),
                             transcript: transcript,
                             control: control)
    }

    public static func stateJSON(_ snapshot: StateSnapshot) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
    }

    /// 用户输入: 优先取显式 userMessage item, 回落到 userInput。
    /// 与 App 层 `SessionStore.turnUserText` 同语义, 复制在 Core 以便共享。
    public static func userText(_ turn: Turn) -> String {
        if let item = turn.items.first(where: { if case .userMessage = $0 { return true }; return false }),
           case .userMessage(_, let text) = item {
            return text
        }
        return turn.userInput
    }

    /// 助手回复: 拼接所有非 app-progress- 的 assistantMessage。
    /// 与 App 层 `SessionStore.turnAssistantText` 同语义。
    public static func assistantText(_ turn: Turn) -> String {
        turn.items.compactMap { item -> String? in
            if case .assistantMessage(let id, let text) = item,
               !id.hasPrefix("app-progress-") { return text }
            return nil
        }.joined(separator: "\n")
    }

    private static func truncate(_ s: String) -> String {
        guard s.count > maxTextLength else { return s }
        let idx = s.index(s.startIndex, offsetBy: maxTextLength)
        return String(s[..<idx]) + "\n…(已截断)"
    }

    // MARK: - H5 page

    /// 渲染 H5 单页。页面静态、无外链资源, 数据全部经 `/api/state` JSON
    /// 获取, DOM 一律用 textContent 写入, 天然免 XSS。
    public static func pageHTML(token: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <title>Tapgo AICoding · 远程控制</title>
        <style>
        :root { --bg:#f5f5f7; --card:#fff; --fg:#1d1d1f; --muted:#6e6e73; --line:#e5e5ea;
                --brand:#4f7cff; --userBg:#e8efff; --ok:#34c759; --warn:#ff9f0a; }
        @media (prefers-color-scheme: dark) {
          :root { --bg:#0d0d0f; --card:#1a1a1e; --fg:#f2f2f5; --muted:#98989f; --line:#2c2c30;
                  --brand:#6f95ff; --userBg:#22304f; }
        }
        * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
        body { margin:0; background:var(--bg); color:var(--fg);
               font:-apple-system-body system-ui,-apple-system,"PingFang SC",sans-serif;
               font-size:16px; }
        header { position:sticky; top:0; z-index:10; background:var(--card);
                 border-bottom:1px solid var(--line); padding:12px 16px;
                 display:flex; align-items:center; gap:10px; }
        header h1 { font-size:17px; margin:0; flex:1; white-space:nowrap; overflow:hidden;
                    text-overflow:ellipsis; }
        #dot { width:9px; height:9px; border-radius:50%; background:var(--ok); flex:none; }
        #dot.off { background:var(--warn); }
        main { padding:12px 12px 140px; max-width:720px; margin:0 auto; }
        select { width:100%; padding:10px 12px; border-radius:10px; border:1px solid var(--line);
                 background:var(--card); color:var(--fg); font-size:15px; margin-bottom:10px; }
        .turn { background:var(--card); border:1px solid var(--line); border-radius:14px;
                padding:12px 14px; margin-bottom:10px; }
        .turn .u { white-space:pre-wrap; word-break:break-word; font-weight:600; }
        .turn .a { white-space:pre-wrap; word-break:break-word; margin-top:8px; line-height:1.55; }
        .turn .a:empty { display:none; }
        .badge { display:inline-block; font-size:12px; border-radius:99px; padding:2px 9px;
                 margin-top:8px; background:var(--warn); color:#fff; }
        .badge.done { background:transparent; color:var(--muted); }
        .meta { font-size:12px; color:var(--muted); margin-top:6px; }
        #tabs { display:flex; gap:8px; padding:10px 12px 0; max-width:720px; margin:0 auto; }
        .tab { flex:1; background:var(--card); color:var(--muted); border:1px solid var(--line);
               font-weight:600; font-size:15px; padding:9px 0; border-radius:10px; }
        .tab.active { color:var(--brand); border-color:var(--brand); }
        .hidden { display:none !important; }
        #ctrlPane { padding:12px 12px 24px; max-width:720px; margin:0 auto; }
        .card { background:var(--card); border:1px solid var(--line); border-radius:14px;
                padding:12px; margin-bottom:10px; }
        .card h2 { font-size:14px; margin:0 0 8px; color:var(--muted); font-weight:600; }
        .row { display:flex; gap:8px; margin-bottom:8px; }
        .row:last-child { margin-bottom:0; }
        .k { flex:1; min-width:52px; background:var(--bg); color:var(--fg);
             border:1px solid var(--line); font-weight:500; font-size:14px; padding:9px 4px; }
        .k:disabled, #shotBtn:disabled, #typeBtn:disabled { opacity:.4; }
        .wide { flex:2; }
        .danger { background:#e5484d; }
        .banner { border-radius:10px; padding:9px 12px; font-size:13px; margin-bottom:10px;
                  background:#fff3e0; color:#8a5300; border:1px solid #f0c987; line-height:1.5; }
        @media (prefers-color-scheme: dark) {
          .banner { background:#3a2c12; color:#ffcf87; border-color:#6b4e1d; }
        }
        #shotWrap { position:relative; border:1px solid var(--line); border-radius:10px;
                    overflow:hidden; background:var(--bg); min-height:110px; }
        #shot { display:block; width:100%; }
        #shotEmpty { position:absolute; inset:0; display:flex; align-items:center;
                     justify-content:center; color:var(--muted); font-size:14px; text-align:center; }
        #ctrlText { width:100%; height:70px; margin-bottom:8px; resize:none; }
        .hint { font-size:12px; color:var(--muted); margin-top:8px; line-height:1.5; }
        #bar { position:fixed; bottom:0; left:0; right:0; background:var(--card);
               border-top:1px solid var(--line); padding:10px 12px calc(10px + env(safe-area-inset-bottom));
               display:flex; gap:8px; max-width:720px; margin:0 auto; }
        textarea { flex:1; resize:none; border:1px solid var(--line); border-radius:12px;
                   padding:10px 12px; font-size:16px; background:var(--bg); color:var(--fg);
                   height:44px; max-height:120px; outline:none; }
        button { border:none; border-radius:12px; background:var(--brand); color:#fff;
                 font-size:16px; padding:0 18px; font-weight:600; }
        button:disabled { opacity:.5; }
        #empty { color:var(--muted); text-align:center; padding:40px 0; }
        </style>
        </head>
        <body>
        <header>
          <span id="dot" class="off"></span>
          <h1 id="title">Tapgo AICoding</h1>
        </header>
        <nav id="tabs">
          <button class="tab active" id="tabChat">会话</button>
          <button class="tab" id="tabCtrl">电脑控制</button>
        </nav>
        <main id="chatPane">
          <select id="threads"></select>
          <div id="list"><div id="empty">正在连接 Mac…</div></div>
        </main>
        <main id="ctrlPane" class="hidden">
          <div id="ctrlBanner" class="banner hidden"></div>
          <div class="card">
            <h2>屏幕</h2>
            <div class="row">
              <button id="shotBtn" class="wide">截屏</button>
              <button id="dblBtn" class="wide k">双击模式: 关</button>
            </div>
            <div id="shotWrap">
              <img id="shot" alt="Mac 屏幕">
              <div id="shotEmpty">点「截屏」查看 Mac 当前画面</div>
            </div>
            <div class="hint">点按画面任意位置 = 在 Mac 对应位置单击; 打开双击模式后为双击。点按后画面自动刷新。</div>
          </div>
          <div class="card">
            <h2>滚动</h2>
            <div class="row">
              <button class="k wide" data-scroll="-5">▲ 上滚</button>
              <button class="k wide" data-scroll="5">▼ 下滚</button>
            </div>
          </div>
          <div class="card">
            <h2>键盘</h2>
            <textarea id="ctrlText" class="k" placeholder="在此输入要打到 Mac 上的文字…"></textarea>
            <div class="row">
              <button id="typeBtn" class="wide">输入到 Mac</button>
            </div>
            <div class="row">
              <button class="k" data-key="return">换行</button>
              <button class="k" data-key="escape">Esc</button>
              <button class="k" data-key="tab">Tab</button>
              <button class="k" data-key="space">空格</button>
              <button class="k" data-key="delete">⌫</button>
              <button class="k" data-key="forwardDelete">⌦</button>
            </div>
            <div class="row">
              <button class="k" data-key="left">←</button>
              <button class="k" data-key="up">↑</button>
              <button class="k" data-key="down">↓</button>
              <button class="k" data-key="right">→</button>
            </div>
          </div>
          <div class="card">
            <h2>媒体</h2>
            <div class="row">
              <button class="k" data-key="volumeUp">音量+</button>
              <button class="k" data-key="volumeDown">音量-</button>
              <button class="k" data-key="mute">静音</button>
            </div>
            <div class="row">
              <button class="k" data-key="brightnessUp">亮度+</button>
              <button class="k" data-key="brightnessDown">亮度-</button>
              <button class="k" data-key="playPause">播放/暂停</button>
            </div>
          </div>
          <div class="card">
            <h2>系统</h2>
            <div class="row">
              <button id="lockBtn" class="k wide danger">锁屏</button>
              <button id="sleepBtn" class="k wide danger">睡眠</button>
            </div>
          </div>
        </main>
        <div id="bar">
          <textarea id="input" placeholder="给当前会话发指令…" rows="1"></textarea>
          <button id="send">发送</button>
        </div>
        <script>
        const TOKEN = \(JSONEncoder.tokenLiteral(token));
        const $ = (id) => document.getElementById(id);
        let lastJSON = "";
        let activeId = null;
        let busy = false;
        let ctrlState = null;
        let dbl = false;
        let shotURL = null;

        function render(s) {
          $("title").textContent = "Tapgo · " + (s.hostname || "Mac");
          activeId = s.activeId;
          const sel = $("threads");
          const keep = sel.value;
          sel.textContent = "";
          for (const t of (s.threads || [])) {
            const opt = document.createElement("option");
            opt.value = t.id;
            opt.textContent = (t.busy ? "▶ " : "") + t.title;
            sel.appendChild(opt);
          }
          if (keep) sel.value = keep;
          if (s.activeId) sel.value = s.activeId;

          const list = $("list");
          list.textContent = "";
          const turns = s.transcript || [];
          if (!turns.length) {
            const e = document.createElement("div"); e.id = "empty";
            e.textContent = "这个会话还没有对话, 在下方发第一条指令。";
            list.appendChild(e);
          }
          for (const t of turns) {
            const card = document.createElement("div"); card.className = "turn";
            const u = document.createElement("div"); u.className = "u";
            u.textContent = t.user; card.appendChild(u);
            const a = document.createElement("div"); a.className = "a";
            a.textContent = t.assistant; card.appendChild(a);
            if (t.running) {
              const b = document.createElement("span"); b.className = "badge";
              b.textContent = t.status === "awaitingApproval" ? "等待 Mac 上确认" : "正在运行…";
              card.appendChild(b);
            } else {
              const m = document.createElement("div"); m.className = "meta";
              m.textContent = t.status === "failed" ? "已失败" :
                              t.status === "interrupted" ? "已中断" : "已完成";
              card.appendChild(m);
            }
            list.appendChild(card);
          }
          busy = turns.length > 0 && turns[turns.length - 1].running;
          ctrlState = s;
          applyCtrlState(s);
          $("dot").classList.remove("off");
        }

        async function refresh() {
          try {
            const r = await fetch("/r/" + TOKEN + "/api/state", { cache: "no-store" });
            if (!r.ok) throw new Error(r.status);
            const text = await r.text();
            if (text === lastJSON) { $("dot").classList.remove("off"); return; }
            lastJSON = text;
            render(JSON.parse(text));
          } catch (e) {
            $("dot").classList.add("off");
          }
        }

        $("threads").addEventListener("change", async (ev) => {
          await fetch("/r/" + TOKEN + "/api/select", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ threadId: ev.target.value })
          });
          lastJSON = "";
          refresh();
        });

        $("input").addEventListener("input", (ev) => {
          ev.target.style.height = "44px";
          ev.target.style.height = Math.min(120, ev.target.scrollHeight) + "px";
        });

        async function send() {
          const input = $("input");
          const text = input.value.trim();
          if (!text || busy) return;
          $("send").disabled = true;
          try {
            await fetch("/r/" + TOKEN + "/api/send", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ text: text })
            });
            input.value = "";
            input.style.height = "44px";
            lastJSON = "";
            await refresh();
          } finally {
            $("send").disabled = false;
          }
        }
        $("send").addEventListener("click", send);
        $("input").addEventListener("keydown", (ev) => {
          if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); send(); }
        });

        // ---------- 电脑控制 (v0.5.17) ----------

        function ctrlReady() {
          const c = ctrlState && ctrlState.control;
          return !!(c && c.enabled && c.accessibilityAllowed);
        }
        function screenReady() {
          const c = ctrlState && ctrlState.control;
          return !!(c && c.enabled && c.screenAllowed);
        }

        function applyCtrlState(s) {
          const c = s.control;
          const banner = $("ctrlBanner");
          if (!c) {
            banner.classList.remove("hidden");
            banner.textContent = "Mac 端 App 版本较旧, 不支持电脑控制。";
          } else if (!c.enabled) {
            banner.classList.remove("hidden");
            banner.textContent = "Mac 端已关闭电脑控制, 请在 Mac 的「移动端远程控制」窗口打开开关。";
          } else if (!c.accessibilityAllowed || !c.screenAllowed) {
            banner.classList.remove("hidden");
            const missing = [];
            if (!c.accessibilityAllowed) missing.push("辅助功能 (点击/键盘/系统操作)");
            if (!c.screenAllowed) missing.push("屏幕录制 (截屏)");
            banner.textContent = "Mac 未授权: " + missing.join("、") +
              "。请在 Mac 端「系统设置 → 隐私与安全性」里授权, 或点 Mac 端弹窗授权。";
          } else {
            banner.classList.add("hidden");
          }
          $("shotBtn").disabled = !screenReady();
          $("typeBtn").disabled = !ctrlReady();
          document.querySelectorAll("[data-key],[data-scroll]").forEach((b) => { b.disabled = !ctrlReady(); });
          $("lockBtn").disabled = !ctrlReady();
          $("sleepBtn").disabled = !ctrlReady();
        }

        function switchTab(toCtrl) {
          $("tabChat").classList.toggle("active", !toCtrl);
          $("tabCtrl").classList.toggle("active", toCtrl);
          $("chatPane").classList.toggle("hidden", toCtrl);
          $("ctrlPane").classList.toggle("hidden", !toCtrl);
          $("bar").classList.toggle("hidden", toCtrl);
        }
        $("tabChat").addEventListener("click", () => switchTab(false));
        $("tabCtrl").addEventListener("click", () => switchTab(true));

        async function ctrl(endpoint, body) {
          try {
            const r = await fetch("/r/" + TOKEN + "/api/ctrl/" + endpoint, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(body)
            });
            if (!r.ok) {
              const j = await r.json().catch(() => ({}));
              if (j.error === "accessibilityPermission") {
                applyCtrlState({ control: { enabled: true, screenAllowed: true, accessibilityAllowed: false } });
              }
              return false;
            }
            return true;
          } catch (e) { return false; }
        }

        async function screenshot() {
          try {
            const r = await fetch("/r/" + TOKEN + "/api/ctrl/screen", { cache: "no-store" });
            if (!r.ok) {
              const j = await r.json().catch(() => ({}));
              const msg = j.error === "screenPermission" ? "Mac 未授予屏幕录制权限, 截屏不可用。" :
                          j.error === "controlDisabled" ? "Mac 端已关闭电脑控制。" : "截屏失败。";
              const empty = $("shotEmpty");
              empty.textContent = msg;
              empty.classList.remove("hidden");
              return;
            }
            const blob = await r.blob();
            if (shotURL) URL.revokeObjectURL(shotURL);
            shotURL = URL.createObjectURL(blob);
            const img = $("shot");
            img.src = shotURL;
            img.onload = () => $("shotEmpty").classList.add("hidden");
          } catch (e) {
            const empty = $("shotEmpty");
            empty.textContent = "网络异常, 稍后再试。";
            empty.classList.remove("hidden");
          }
        }
        $("shotBtn").addEventListener("click", screenshot);

        $("dblBtn").addEventListener("click", () => {
          dbl = !dbl;
          $("dblBtn").textContent = "双击模式: " + (dbl ? "开" : "关");
        });

        $("shot").addEventListener("click", async (ev) => {
          if (!ctrlReady()) return;
          const r = ev.target.getBoundingClientRect();
          const x = (ev.clientX - r.left) / r.width;
          const y = (ev.clientY - r.top) / r.height;
          if (x < 0 || x > 1 || y < 0 || y > 1) return;
          await ctrl("click", { x: x, y: y, double: dbl });
          setTimeout(screenshot, 600);
        });

        document.querySelectorAll("[data-scroll]").forEach((b) => {
          b.addEventListener("click", () => ctrl("scroll", { dy: parseFloat(b.dataset.scroll) }));
        });
        document.querySelectorAll("[data-key]").forEach((b) => {
          b.addEventListener("click", () => ctrl("key", { key: b.dataset.key }));
        });

        $("typeBtn").addEventListener("click", async () => {
          const v = $("ctrlText").value;
          if (!v || !ctrlReady()) return;
          await ctrl("type", { text: v });
          $("ctrlText").value = "";
        });

        $("lockBtn").addEventListener("click", async () => {
          if (confirm("确定要锁屏 Mac?") && ctrlReady()) await ctrl("cmd", { action: "lock" });
        });
        $("sleepBtn").addEventListener("click", async () => {
          if (confirm("确定要让 Mac 睡眠?") && ctrlReady()) await ctrl("cmd", { action: "sleep" });
        });

        setInterval(refresh, 2000);
        refresh();
        </script>
        </body>
        </html>
        """
    }
}

private extension JSONEncoder {
    /// 把 token 以 JS 字符串字面量形式安全内嵌 (token 字符集本身有限, 这里
    /// 只是防御性转义)。
    static func tokenLiteral(_ token: String) -> String {
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "<", with: "\\u003c")
        return "\"\(escaped)\""
    }
}
