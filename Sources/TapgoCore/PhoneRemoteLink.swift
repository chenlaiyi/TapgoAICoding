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

    /// 本机隧道进程在命令行里的唯一特征串 (pkill -f 用)。App 被强杀时
    /// ssh 子进程会变孤儿并继续占着服务器转发端口, 新隧道会报
    /// "remote port forwarding failed"; 拉起新隧道前用它清理残留。
    public static func tunnelProcessPattern(serverForwardPort: Int, localPort: Int) -> String {
        "127.0.0.1:\(serverForwardPort):127.0.0.1:\(localPort) \(relaySSHDestination)"
    }

    /// 清理服务器端僵尸转发会话的参数: 本机 ssh 非正常死亡时, 服务器 sshd
    /// 可能长时间察觉不到 (半开连接), 转发监听还在但通道已死, 新隧道绑不上
    /// 端口。端口三机独占, `fuser -k` 只影响自己的端口, 不会误伤他人。
    public static func remoteCleanupArguments(serverForwardPort: Int) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            relaySSHDestination,
            "fuser -k -n tcp \(serverForwardPort) 2>/dev/null; true",
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
        // MARK: 项目切换 (v0.5.20) — 对齐 ZCode 工作区/任务形态。
        /// POST /r/<token>/api/project `{"projectId": "..."}` — 切换活动项目,
        /// Mac 端会自动选中该项目最近的会话。
        case project(id: String)
        /// POST /r/<token>/api/new `{"projectId": "..."}` — 在指定项目下新建
        /// 会话并切换过去。
        case newSession(projectId: String)
        /// POST /r/<token>/api/attach — 手机上传图片附件 (base64), 落到
        /// Mac 待发附件, 随下一条消息一起发送。
        case attach(name: String, dataBase64: String)
        /// GET /r/<token>/img/<turnId>/<index> — 会话内用户消息图片。
        case turnImage(turnId: String, index: Int)
        /// GET /r/<token>/pending/<index> — 待发附件缩略图。
        case pendingImage(index: Int)
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
        case ["api", "project"]:
            guard method == "POST", let id = jsonStringField(body, "projectId"), !id.isEmpty else {
                return .failure(.badRequest)
            }
            return .success(.project(id: id))
        case ["api", "new"]:
            guard method == "POST", let pid = jsonStringField(body, "projectId"), !pid.isEmpty else {
                return .failure(.badRequest)
            }
            return .success(.newSession(projectId: pid))
        case ["api", "attach"]:
            guard method == "POST",
                  let name = jsonStringField(body, "name"), !name.isEmpty,
                  let data = jsonStringField(body, "data"), !data.isEmpty
            else { return .failure(.badRequest) }
            return .success(.attach(name: name, dataBase64: data))
        case let arr where arr.count == 3 && arr[0] == "img":
            let turnId = arr[1]
            let idxStr = arr[2]
            guard method == "GET" || method == "HEAD", let idx = Int(idxStr), idx >= 0 else {
                return .failure(.badRequest)
            }
            return .success(.turnImage(turnId: turnId, index: idx))
        case let arr where arr.count == 2 && arr[0] == "pending":
            let idxStr = arr[1]
            guard method == "GET" || method == "HEAD", let idx = Int(idxStr), idx >= 0 else {
                return .failure(.badRequest)
            }
            return .success(.pendingImage(index: idx))
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
    /// 请求 body 最大字节数 (20MB — 手机上传图片附件走 base64, 有 1.33 倍膨胀)。
    public static let maxBodyBytes = 20_000_000

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

    public struct ProjectInfo: Codable, Equatable {
        public var id: String
        public var name: String
        /// 项目根目录 (H5 上以截断路径展示)。
        public var path: String
        public var threadCount: Int
        /// 本地项目 (H5 显示「本地」标签)。
        public var isLocal: Bool
        /// 项目最近活跃时间 (H5 显示「更新于 …」)。
        public var lastActivityAt: Date
    }

    /// App 层喂给 buildState 的项目种子 (Core 不依赖 WorkspaceStore 类型)。
    public struct ProjectSeed: Equatable {
        public let id: String
        public let name: String
        public let path: String
        public let lastActivityAt: Date
        public let isLocal: Bool

        public init(id: String, name: String, path: String,
                    lastActivityAt: Date, isLocal: Bool = true) {
            self.id = id
            self.name = name
            self.path = path
            self.lastActivityAt = lastActivityAt
            self.isLocal = isLocal
        }
    }

    public struct ThreadInfo: Codable, Equatable {
        public var id: String
        public var title: String
        public var updatedAt: Date
        public var turnCount: Int
        /// 最近一个 turn 正在运行或等待确认。
        public var busy: Bool
        /// 所属项目 (未分类会话为 nil)。
        public var projectId: String?
    }

    public struct TranscriptTurn: Codable, Equatable {
        public var id: String
        public var user: String
        public var status: String
        /// 助手回复原文 (降级/搜索用)。
        public var assistant: String
        /// 助手回复的 Markdown 渲染结果 (已转义的安全 HTML, H5 直接 innerHTML)。
        public var assistantHTML: String
        /// 用户附带图片张数 (H5 经 /img/<turnId>/<i> 取缩略图)。
        public var userImageCount: Int
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
        /// 当前模型名 (composer 底栏展示, 如 "MiniMax-M3")。
        public var model: String?
        /// Mac 端待发附件图片张数 (手机上传后 >0, 发送后清零)。
        public var attachedCount: Int
        /// 项目列表 (按最近活跃倒序) + 活动项目; v0.5.20 项目切换用。
        public var projects: [ProjectInfo]
        public var activeProjectId: String?
    }

    /// 从 SessionStore 的数据构建 H5 需要的全量快照。纯函数, 方便单测。
    public static func buildState(threads: [Thread],
                                  activeId: String?,
                                  rev: Int,
                                  hostname: String,
                                  appVersion: String,
                                  control: ControlStatus? = nil,
                                  projects: [ProjectSeed] = [],
                                  activeProjectId: String? = nil,
                                  model: String? = nil,
                                  attachedCount: Int = 0,
                                  now: Date = Date()) -> StateSnapshot {
        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxThreads)
        let infos = sorted.map { t -> ThreadInfo in
            ThreadInfo(id: t.id,
                       title: truncate(t.title.isEmpty ? "未命名会话" : t.title),
                       updatedAt: t.updatedAt,
                       turnCount: t.turns.count,
                       busy: t.turns.last.map { $0.status == .running || $0.status == .awaitingApproval } ?? false,
                       projectId: t.projectId)
        }
        var transcript: [TranscriptTurn] = []
        if let active = threads.first(where: { $0.id == activeId }) ?? threads.first {
            transcript = active.turns.suffix(maxTranscriptTurns).map { turn in
                let assistant = truncate(assistantText(turn))
                return TranscriptTurn(id: turn.id,
                                      user: truncate(userText(turn)),
                                      status: turn.status.rawValue,
                                      assistant: assistant,
                                      assistantHTML: markdownHTML(assistant),
                                      userImageCount: turn.userImagePaths.count,
                                      running: turn.status == .running || turn.status == .awaitingApproval)
            }
        }
        // 项目按各自会话的最近活跃时间倒序; 没有会话的项目用项目自身
        // lastActivityAt 兜底, 保证新建项目也能排进来。
        let lastActiveByProject = Dictionary(grouping: threads, by: \.projectId)
            .compactMapValues { $0.map(\.updatedAt).max() }
        let projectInfos = projects
            .map { seed -> (ProjectSeed, Date) in
                (seed, max(seed.lastActivityAt, lastActiveByProject[seed.id] ?? .distantPast))
            }
            .sorted { $0.1 > $1.1 }
            .map { seed, activity in
                ProjectInfo(id: seed.id,
                            name: seed.name,
                            path: seed.path,
                            threadCount: threads.filter { $0.projectId == seed.id }.count,
                            isLocal: seed.isLocal,
                            lastActivityAt: activity)
            }
        return StateSnapshot(rev: rev,
                             hostname: hostname,
                             appVersion: appVersion,
                             linkVersion: PhoneRemote.linkVersion,
                             activeId: activeId ?? threads.first?.id,
                             threads: Array(infos),
                             transcript: transcript,
                             control: control,
                             model: model,
                             attachedCount: attachedCount,
                             projects: projectInfos,
                             activeProjectId: activeProjectId)
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

    // MARK: - Markdown → 安全 HTML (v0.5.23 输出可读性)

    /// HTML 转义: & < > " '。属性值 (href 等) 用这个全量版。
    public static func escapeHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&#39;")
        return out
    }

    /// 文本内容转义: 只转 & < >, 保留引号原样 —— 代码块里的
    /// `let s = "hi"` 才不会变成 `&quot;hi&quot;`。
    public static func escapeText(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }

    /// 把助手回复渲染成 H5 直接 innerHTML 的 HTML。
    /// 复用 Mac 端同款 `MarkdownLite` 解析器, 标题/列表/代码块/行内代码/
    /// 引用/表格/任务清单都有对应排版。
    public static func markdownHTML(_ text: String) -> String {
        MarkdownLite.parse(text).map { blockHTML($0) }.joined()
    }

    private static func blockHTML(_ seg: MarkdownSegment) -> String {
        switch seg {
        case .text(let s):
            return paragraphHTML(s)
        case .codeFence(let code, let lang):
            let label = lang.map { "<span class=\"codeLang\">\(escapeHTML($0))</span>" } ?? ""
            return "<pre class=\"codeBlock\">\(label)<code>\(escapeText(code))</code></pre>"
        case .heading(let level, let content):
            let tag = level <= 2 ? "h3" : "h4"
            return "<\(tag)>\(inlineHTML(content))</\(tag)>"
        case .blockquote(let content):
            let inner = content.map { inlineHTML([$0]) }.joined(separator: "<br>")
            return "<blockquote>\(inner)</blockquote>"
        case .horizontalRule:
            return "<hr>"
        case .bulletList(let items):
            let lis = items.map { "<li>\(inlineHTML($0))</li>" }.joined()
            return "<ul>\(lis)</ul>"
        case .numberedList(let items):
            let lis = items.map { "<li>\(inlineHTML($0))</li>" }.joined()
            return "<ol>\(lis)</ol>"
        case .taskList(let items):
            let lis = items.map { item -> String in
                let box = item.checked ? "☑" : "☐"
                return "<li class=\"task\">\(box)&nbsp;\(inlineHTML(item.content))</li>"
            }.joined()
            return "<ul class=\"tasks\">\(lis)</ul>"
        case .table(let headers, let rows):
            let ths = headers.map { "<th>\(escapeText($0))</th>" }.joined()
            let trs = rows.map { row in
                "<tr>" + row.map { "<td>\(escapeText($0))</td>" }.joined() + "</tr>"
            }.joined()
            return "<div class=\"tblWrap\"><table><thead><tr>\(ths)</tr></thead><tbody>\(trs)</tbody></table></div>"
        case .bold(let s):
            return paragraphHTML("**\(s)**")
        case .strikethrough(let s):
            return paragraphHTML("~~\(s)~~")
        case .link(let title, let url):
            return "<p>\(linkHTML(title: title, url: url))</p>"
        case .image(let alt, let url):
            // H5 不外链图片 (离线可用), 降级为链接。
            return "<p>\(linkHTML(title: alt.isEmpty ? "图片" : alt, url: url))</p>"
        case .inline(let s):
            return paragraphHTML("`\(s)`")
        }
    }

    /// 非空文本段 → <p>; 行内语法 (加粗/行内代码/链接) 一并解析。
    private static func paragraphHTML(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        return "<p>\(inlineHTML(MarkdownLite.parseInline(t)))</p>"
    }

    /// 行内片段 → HTML (全部转义后包标签)。
    private static func inlineHTML(_ segs: [MarkdownSegment]) -> String {
        segs.map { seg -> String in
            switch seg {
            case .text(let s):
                return escapeText(s).replacingOccurrences(of: "\n", with: "<br>")
            case .inline(let s):
                return "<code>\(escapeText(s))</code>"
            case .bold(let s):
                return "<strong>\(escapeText(s))</strong>"
            case .strikethrough(let s):
                return "<del>\(escapeText(s))</del>"
            case .link(let title, let url):
                return linkHTML(title: title, url: url)
            case .image(let alt, _):
                return escapeText(alt)
            case .heading(let level, let content):
                return inlineHTML(content) + " "
            case .blockquote(let content):
                return content.map { inlineHTML([$0]) }.joined()
            case .horizontalRule:
                return ""
            case .bulletList(let items), .numberedList(let items):
                return items.map { inlineHTML($0) }.joined(separator: " ")
            case .taskList(let items):
                return items.map { inlineHTML($0.content) }.joined(separator: " ")
            case .codeFence(let code, _):
                return "<code>\(escapeText(code))</code>"
            case .table(let headers, let rows):
                // 表格是块级元素, 行内出现时防御性降级为纯文本。
                return escapeText((headers + rows.flatMap { $0 }).joined(separator: " "))
            }
        }.joined()
    }

    /// 链接: 仅 http/https 可点, 其它 scheme 降级为纯文本。
    private static func linkHTML(title: String, url: String) -> String {
        let lowered = url.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else {
            return escapeText(title)
        }
        return "<a href=\"\(escapeHTML(url))\" target=\"_blank\" rel=\"noopener noreferrer\">\(escapeText(title))</a>"
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
        #dot { width:9px; height:9px; border-radius:50%; background:var(--ok); flex:none; }
        #dot.off { background:var(--warn); }
        main { padding:12px 12px 190px; max-width:720px; margin:0 auto; }
        /* 对话输出: 用户右侧气泡 + 助手正文 (仿 ZCode 输出形态) */
        .turnGroup { margin-bottom:18px; }
        .msgUser { margin-left:auto; max-width:86%; width:fit-content;
                   background:var(--userBg); border-radius:16px 16px 4px 16px;
                   padding:10px 13px; white-space:pre-wrap; word-break:break-word;
                   font-weight:500; font-size:15.5px; }
        .msgA { margin-top:10px; word-break:break-word;
                line-height:1.6; font-size:15.5px; }
        .msgA p { margin:0 0 8px; }
        .msgA p:last-child { margin-bottom:0; }
        .msgA h3 { font-size:16px; margin:12px 0 6px; }
        .msgA h4 { font-size:15px; margin:9px 0 5px; }
        .msgA ul, .msgA ol { margin:0 0 8px; padding-left:20px; }
        .msgA li { margin:2px 0; line-height:1.5; }
        .msgA li.task { list-style:none; margin-left:-18px; }
        .msgA code { font-family:ui-monospace,Menlo,monospace; font-size:13px;
                     background:var(--userBg); color:var(--brand); border-radius:5px;
                     padding:1px 5px; word-break:break-all; }
        .msgA pre.codeBlock { background:#0b0b0e; color:#e8e8ed; border:1px solid var(--line);
                              border-radius:10px; padding:24px 12px 10px; overflow-x:auto;
                              margin:0 0 8px; }
        .msgA pre.codeBlock code { background:none; color:inherit; padding:0;
                                   font-size:12.5px; line-height:1.5; white-space:pre; }
        .msgA .codeLang { position:absolute; top:5px; right:9px; font-size:11px;
                          color:var(--muted); }
        .msgA pre.codeBlock { position:relative; }
        .msgA blockquote { margin:0 0 8px; padding:6px 12px; border-left:3px solid var(--brand);
                           color:var(--muted); background:var(--card); border-radius:0 8px 8px 0; }
        .msgA a { color:var(--brand); text-decoration:underline; word-break:break-all; }
        .msgA hr { border:none; border-top:1px solid var(--line); margin:10px 0; }
        .msgA .tblWrap { overflow-x:auto; margin:0 0 8px; border:1px solid var(--line);
                         border-radius:10px; }
        .msgA table { border-collapse:collapse; width:100%; font-size:13px; }
        .msgA th, .msgA td { padding:6px 9px; border-bottom:1px solid var(--line); text-align:left; }
        .msgA th { background:var(--card); font-weight:600; }
        .badge { display:inline-block; font-size:12px; border-radius:99px; padding:3px 10px;
                 margin-top:8px; background:var(--warn); color:#fff; }
        .badge.runPulse { animation:pulse 1.4s ease-in-out infinite; }
        @keyframes pulse { 0%,100% { opacity:1; } 50% { opacity:.45; } }
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
        #bar { position:fixed; bottom:0; left:0; right:0; padding:8px 10px calc(8px + env(safe-area-inset-bottom));
               background:linear-gradient(transparent, var(--bg) 26%); }
        /* 顶部项目切换器 (替代软件标题) */
        #projChip { flex:1; min-width:0; display:flex; align-items:center; gap:7px;
                    background:var(--bg); border:1px solid var(--line); border-radius:10px;
                    padding:8px 11px; font-weight:600; font-size:15px; cursor:pointer; }
        #projChip #projName { flex:1; min-width:0; white-space:nowrap; overflow:hidden;
                              text-overflow:ellipsis; }
        #projChip .cIcon { color:var(--muted); font-size:14px; }
        #projChip .pChev { color:var(--muted); font-size:11px; }
        /* Composer 卡片 (仿 ZCode 输入区): 大输入区 + 底部工具行 */
        .composer { max-width:720px; margin:0 auto; background:var(--card);
                    border:1px solid var(--line); border-radius:20px; padding:13px 15px 10px;
                    box-shadow:0 4px 18px rgba(0,0,0,.10); }
        .composer textarea { width:100%; border:none; background:transparent; resize:none;
                             font-size:16px; color:var(--fg); min-height:52px; max-height:150px;
                             padding:2px 2px 6px; outline:none; }
        .composerBar { display:flex; align-items:center; gap:6px; }
        .barIcon { background:transparent; border:none; color:var(--muted); width:32px; height:32px;
                   padding:0; display:flex; align-items:center; justify-content:center;
                   border-radius:9px; flex:none; }
        .barIcon svg { display:block; }
        .barIcon.attn { color:#ff9f0a; }
        .spin { width:15px; height:15px; border:2px solid var(--line); border-top-color:var(--muted);
                border-radius:50%; animation:rot .9s linear infinite; flex:none; margin:0 3px; }
        @keyframes rot { to { transform:rotate(360deg); } }
        .modelSel { display:flex; align-items:center; gap:4px; color:var(--fg); font-size:14px;
                    font-weight:600; margin-left:auto; white-space:nowrap;
                    background:transparent; border:none; padding:4px 2px; }
        .brainWrap { position:relative; display:flex; align-items:center; justify-content:center;
                     width:28px; height:28px; flex:none; color:var(--muted);
                     background:transparent; border:none; padding:0; cursor:pointer; }
        #attRow { display:flex; align-items:center; gap:4px; flex-wrap:wrap; font-size:12px;
                  color:var(--muted); background:var(--bg); border:1px dashed var(--line);
                  border-radius:8px; padding:5px 9px; margin-bottom:6px; }
        #attRow.uploading { color:var(--brand); border-color:var(--brand); }
        .attThumb { width:36px; height:36px; border-radius:8px; object-fit:cover; flex:none; }
        .msgImg { display:block; max-width:100%; max-height:220px; border-radius:10px;
                  margin-top:8px; }
        #modelSheet { position:fixed; inset:0; z-index:50; background:rgba(0,0,0,.5);
                      display:flex; align-items:flex-end; justify-content:center; }
        .sheetCard { background:var(--card); width:100%; max-width:720px;
                     border-radius:18px 18px 0 0; padding:16px 16px calc(16px + env(safe-area-inset-bottom)); }
        .sheetTitle { font-weight:700; font-size:16px; margin-bottom:10px; }
        .modelRow { display:flex; align-items:center; gap:8px; width:100%; text-align:left;
                    background:var(--bg); color:var(--fg); border:1px solid var(--line);
                    border-radius:10px; padding:11px 13px; font-size:15px; font-weight:600;
                    margin-bottom:8px; }
        .modelRow.cur { border-color:var(--brand); color:var(--brand); }
        .modelRow .curTag { margin-left:auto; font-size:11px; font-weight:600; }
        .sheetHint { font-size:12px; color:var(--muted); line-height:1.5; margin:2px 0 12px; }
        .sheetCloseBtn { width:100%; background:var(--bg); color:var(--fg);
                         border:1px solid var(--line); padding:10px 0; font-weight:600; }
        .modelSel .pChev { color:var(--muted); font-size:11px; }
        .brainWrap { position:relative; display:flex; align-items:center; justify-content:center;
                     width:28px; height:28px; flex:none; color:var(--muted); }
        .bdot { position:absolute; right:1px; bottom:3px; width:7px; height:7px; border-radius:50%;
                background:var(--line); }
        .bdot.on { background:var(--ok); }
        #sendBtn { width:42px; height:42px; border-radius:50%; background:#fff; color:#101013;
                   font-size:18px; padding:0; margin-left:2px; flex:none;
                   display:flex; align-items:center; justify-content:center;
                   box-shadow:0 1px 6px rgba(0,0,0,.22); }
        #sendBtn:disabled { opacity:.4; }
        /* 空会话时段问候 (仿 ZCode 首屏) */
        #greet { text-align:center; padding:56px 16px 24px; }
        #greet .gLogo { font-size:46px; line-height:1; opacity:.92; }
        #greet .gText { font-size:22px; font-weight:700; margin-top:18px; }
        #greet .gSub { font-size:13px; color:var(--muted); margin-top:8px; }
        button { border:none; border-radius:12px; background:var(--brand); color:#fff;
                 font-size:16px; padding:0 18px; font-weight:600; }
        button:disabled { opacity:.5; }
        #empty { color:var(--muted); text-align:center; padding:40px 0; }
        /* 项目/会话列表页 (仿 ZCode 工作区与任务) */
        .bannerInfo { background:var(--card); color:var(--muted); border:1px solid var(--line); }
        .projCard { background:var(--card); border:1px solid var(--line); border-radius:14px;
                    margin-bottom:10px; overflow:hidden; }
        .projHead { display:flex; align-items:center; gap:10px; padding:12px 14px; }
        .projHead .pIcon { font-size:20px; flex:none; }
        .projName { font-weight:700; font-size:16px; display:flex; align-items:center; gap:6px; }
        .tagLocal { font-size:11px; color:var(--muted); border:1px solid var(--line);
                    border-radius:99px; padding:1px 7px; font-weight:500; }
        .projPath { font-size:12px; color:var(--muted); margin-top:2px;
                    white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .upd { font-size:12px; color:var(--muted); margin-top:2px; }
        .projInfo { flex:1; min-width:0; }
        .projMeta { margin-left:auto; text-align:right; color:var(--muted); font-size:12px; flex:none; }
        .plus { width:36px; height:34px; border-radius:10px; background:var(--bg); color:var(--fg);
                border:1px solid var(--line); font-size:20px; font-weight:500; padding:0; flex:none; }
        .chev { color:var(--muted); font-size:13px; flex:none; width:16px; text-align:center; }
        .sessRows { border-top:1px solid var(--line); }
        .sessRow { display:flex; align-items:center; gap:8px; padding:11px 14px;
                   border-bottom:1px solid var(--line); }
        .sessRow:last-child { border-bottom:none; }
        .sessTitle { flex:1; min-width:0; white-space:nowrap; overflow:hidden;
                     text-overflow:ellipsis; font-size:15px; }
        .sessTime { color:var(--muted); font-size:12px; flex:none; width:44px; text-align:right; }
        .sbadge { flex:none; font-size:11px; border-radius:99px; padding:2px 9px; font-weight:600; }
        .sbadge.run { background:var(--warn); color:#fff; }
        .sbadge.done { background:rgba(52,199,89,.16); color:var(--ok); }
        .dotCur { width:7px; height:7px; border-radius:50%; background:var(--brand); flex:none; }
        .listHead { display:flex; align-items:center; gap:10px; margin-bottom:10px; }
        .ghost { background:var(--card); color:var(--fg); border:1px solid var(--line);
                 width:38px; height:38px; padding:0; font-size:18px; flex:none; }
        .lt1 { font-weight:700; font-size:17px; }
        .lt2 { font-size:12px; color:var(--muted); margin-top:2px; }
        .pEmpty { color:var(--muted); text-align:center; padding:40px 0; }
        </style>
        </head>
        <body>
        <header>
          <span id="dot" class="off"></span>
          <div id="projChip" aria-label="切换项目, 查看项目与会话列表">
            <span class="cIcon">📁</span>
            <span id="projName">…</span>
            <span class="pChev">▾</span>
          </div>
        </header>
        <nav id="tabs">
          <button class="tab active" id="tabChat">会话</button>
          <button class="tab" id="tabCtrl">电脑控制</button>
        </nav>
        <main id="chatPane">
          <div id="list"><div id="empty">正在连接 Mac…</div></div>
        </main>
        <main id="listPane" class="hidden">
          <div class="banner bannerInfo">本次连接可以查看当前设备上的项目、任务和会话; 二维码失效后需要回到 Mac 端重新连接。</div>
          <div class="listHead">
            <button id="backBtn" class="ghost">←</button>
            <div style="flex:1; min-width:0;">
              <div class="lt1">项目与会话</div>
              <div class="lt2" id="projStats">…</div>
            </div>
          </div>
          <div id="projects"><div class="pEmpty">正在加载项目…</div></div>
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
          <input type="file" id="fileInput" accept="image/*" multiple class="hidden">
          <div class="composer">
            <div id="attRow" class="hidden">
              <span id="attThumbs"></span>
              <span id="attMsg"></span>
            </div>
            <textarea id="input" placeholder="向 Tapgo 提问…" rows="2"></textarea>
            <div class="composerBar">
              <button class="barIcon" id="newBtn" aria-label="上传图片附件">
                <svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>
              </button>
              <button class="barIcon" id="shieldBtn" aria-label="电脑控制状态, 点击查看">
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l7 3v5c0 4.6-3 8.1-7 10-4-1.9-7-5.4-7-10V6l7-3z"/><path d="M12 8v4.2"/><circle cx="12" cy="15.4" r="0.9" fill="currentColor" stroke="none"/></svg>
              </button>
              <span class="spin hidden" id="busySpin"></span>
              <button class="modelSel" id="modelBtn" aria-label="选择模型"><span id="modelName">…</span><span class="pChev">▾</span></button>
              <button class="brainWrap" id="brainBtn" aria-label="电脑控制就绪状态, 点击查看">
                <svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 4a3 3 0 0 0-3 3 3 3 0 0 0-2 2.8c0 .9.4 1.7 1 2.2a3 3 0 0 0 .5 4.6A3 3 0 0 0 9.5 20c1 0 2-.5 2.5-1.4V5.4A3 3 0 0 0 9.5 4z"/><path d="M14.5 4a3 3 0 0 1 3 3 3 3 0 0 1 2 2.8c0 .9-.4 1.7-1 2.2a3 3 0 0 1-.5 4.6A3 3 0 0 1 14.5 20c-1 0-2-.5-2.5-1.4V5.4a3 3 0 0 1 2.5-1.4z"/></svg>
                <span class="bdot" id="brainDot"></span>
              </button>
              <button id="sendBtn" aria-label="发送">
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>
              </button>
            </div>
          </div>
        </div>
        <div id="modelSheet" class="hidden">
          <div class="sheetCard">
            <div class="sheetTitle">选择模型</div>
            <div id="modelList"></div>
            <div class="sheetHint">模型列表来自 Mac 端 codex 配置; 在 Mac 端添加更多模型后会自动出现在这里。</div>
            <button id="sheetClose" class="sheetCloseBtn">关闭</button>
          </div>
        </div>
        <script>
        const TOKEN = \(JSONEncoder.tokenLiteral(token));
        // API 前缀自适应: 直连时页面在 /r/<token>/, BASE = "/";
        // 公网中继时页面在 /remote/<machine>/r/<token>/, BASE =
        // "/remote/<machine>/" — 必须带上, 否则 /r/* 会被域名根的
        // 反代吞掉返回 404, 页面永远停在"正在连接 Mac…"。
        const BASE = location.pathname.replace(/\\/r\\/[^\\/]+\\/?$/, "/");
        const $ = (id) => document.getElementById(id);
        let lastJSON = "";
        let activeId = null;
        let activeProjectId = null;
        let busy = false;
        let ctrlState = null;
        let dbl = false;
        let shotURL = null;

        function render(s) {
          document.title = "Tapgo · " + (s.hostname || "Mac");
          activeId = s.activeId;
          lastState = s;

          // 项目 chip: 当前活动项目名 (仿 ZCode 输入框上方)。
          const activeProj = (s.projects || []).find((p) => p.id === s.activeProjectId);
          $("projName").textContent = activeProj ? activeProj.name : "未分类会话";
          renderProjects(s);

          const list = $("list");
          list.textContent = "";
          const turns = s.transcript || [];
          if (!turns.length) {
            const g = document.createElement("div"); g.id = "greet";
            const logo = document.createElement("div"); logo.className = "gLogo";
            logo.textContent = "}";
            const gt = document.createElement("div"); gt.className = "gText";
            const h = new Date().getHours();
            gt.textContent = h < 11 ? "早上好呀" : h < 13 ? "中午好呀" : h < 18 ? "下午好呀" : "晚上好呀";
            const gs = document.createElement("div"); gs.className = "gSub";
            gs.textContent = "在下方输入任务, 我在 Mac 上帮你完成。";
            g.append(logo, gt, gs);
            list.appendChild(g);
          }
          for (const t of turns) {
            const group = document.createElement("div"); group.className = "turnGroup";
            const u = document.createElement("div"); u.className = "msgUser";
            u.textContent = t.user;
            const imgCount = t.userImageCount || 0;
            for (let i = 0; i < imgCount; i++) {
              const im = document.createElement("img");
              im.className = "msgImg";
              im.loading = "lazy";
              im.alt = "附件图片";
              im.src = BASE + "r/" + TOKEN + "/img/" + encodeURIComponent(t.id) + "/" + i;
              u.appendChild(im);
            }
            group.appendChild(u);
            if (t.assistantHTML) {
              const a = document.createElement("div"); a.className = "msgA";
              a.innerHTML = t.assistantHTML;
              group.appendChild(a);
            }
            if (t.running) {
              const b = document.createElement("span"); b.className = "badge runPulse";
              b.textContent = t.status === "awaitingApproval" ? "等待 Mac 上确认" : "正在运行…";
              group.appendChild(b);
            } else if (t.status === "failed" || t.status === "interrupted") {
              const m = document.createElement("div"); m.className = "meta";
              m.textContent = t.status === "failed" ? "已失败" : "已中断";
              group.appendChild(m);
            }
            list.appendChild(group);
          }
          busy = turns.length > 0 && turns[turns.length - 1].running;
          $("sendBtn").disabled = busy;
          activeProjectId = s.activeProjectId || null;
          // 待发附件 (上传后 >0, 发送后 Mac 端清零): 缩略图 + 计数。
          const att = s.attachedCount || 0;
          $("attRow").classList.toggle("hidden", att === 0);
          const thumbs = $("attThumbs");
          thumbs.textContent = "";
          for (let i = 0; i < att; i++) {
            const im = document.createElement("img");
            im.className = "attThumb";
            im.src = BASE + "r/" + TOKEN + "/pending/" + i;
            thumbs.appendChild(im);
          }
          $("attMsg").textContent = att > 0 ? " 已附 " + att + " 张图片, 随下一条消息一起发送" : "";
          // composer 底栏状态 (仿 ZCode: 转圈 / 模型名 / 大脑绿点 / 盾牌)
          $("modelName").textContent = s.model || "MiniMax-M3";
          $("busySpin").classList.toggle("hidden", !busy);
          const ctl = s.control;
          const ctrlReadyAll = !!(ctl && ctl.enabled && ctl.accessibilityAllowed && ctl.screenAllowed);
          $("brainDot").classList.toggle("on", ctrlReadyAll);
          $("shieldBtn").classList.toggle("attn", !!(ctl && ctl.enabled && !ctrlReadyAll));
          ctrlState = s;
          applyCtrlState(s);
          $("dot").classList.remove("off");
        }

        let failuresCount = 0;

        function showStuck(status) {
          // 首屏还没成功渲染过才提示, 避免轮询瞬断抹掉已加载的对话。
          if (lastJSON !== "") return;
          const e = $("empty"); if (!e) return;
          e.textContent = status === 403
            ? "链接已失效 (403): 二维码可能已轮换, 请在 Mac 上刷新二维码后重扫。"
            : status === 404
            ? "服务路径不通 (404): 请确认 Mac 端 App 已更新。"
            : "无法连接 Mac, 请检查手机网络后稍候…";
        }

        let lastState = null;
        const expanded = {};
        let inList = false;

        function ago(ms) {
          const d = Date.now() - ms;
          if (d < 60000) return "刚刚";
          if (d < 3600000) return Math.floor(d / 60000) + " 分钟";
          if (d < 86400000) return Math.floor(d / 3600000) + " 小时";
          return Math.floor(d / 86400000) + " 天";
        }

        function renderProjects(s) {
          if (!s || !$("projects")) return;
          const projs = s.projects || [];
          const threads = s.threads || [];
          $("projStats").textContent = (s.hostname ? s.hostname + " · " : "") + projs.length + " 个项目 · " + threads.length + " 个会话";
          const pc = $("projects");
          pc.textContent = "";
          if (!projs.length) {
            const e = document.createElement("div"); e.className = "pEmpty";
            e.textContent = "还没有项目, 在 Mac 端添加后再来。";
            pc.appendChild(e);
            return;
          }
          for (const p of projs) {
            const isOpen = expanded[p.id] !== undefined
              ? expanded[p.id] : (p.id === s.activeProjectId);
            const card = document.createElement("div"); card.className = "projCard";
            const head = document.createElement("div"); head.className = "projHead";
            const ic = document.createElement("span"); ic.className = "pIcon"; ic.textContent = "📁";
            const info = document.createElement("div"); info.className = "projInfo";
            const n1 = document.createElement("div"); n1.className = "projName";
            n1.textContent = p.name;
            const tag = document.createElement("span"); tag.className = "tagLocal";
            tag.textContent = p.isLocal ? "本地" : "远程";
            n1.appendChild(tag);
            const n2 = document.createElement("div"); n2.className = "projPath"; n2.textContent = p.path;
            const upd = document.createElement("div"); upd.className = "upd";
            upd.textContent = "更新于 " + ago(p.lastActivityAt);
            info.append(n1, n2, upd);
            const meta = document.createElement("div"); meta.className = "projMeta";
            meta.textContent = p.threadCount + " 个会话";
            const plus = document.createElement("button"); plus.className = "plus";
            plus.textContent = "+"; plus.setAttribute("aria-label", "在 " + p.name + " 新建会话");
            plus.addEventListener("click", (ev) => { ev.stopPropagation(); newSession(p.id); });
            const chev = document.createElement("span"); chev.className = "chev";
            chev.textContent = isOpen ? "▾" : "▸";
            head.append(ic, info, meta, plus, chev);
            head.addEventListener("click", () => {
              expanded[p.id] = !(expanded[p.id] !== undefined ? expanded[p.id] : p.id === s.activeProjectId);
              renderProjects(lastState);
            });
            card.appendChild(head);
            if (isOpen) {
              const rows = document.createElement("div"); rows.className = "sessRows";
              const sess = threads.filter((t) => t.projectId === p.id);
              if (!sess.length) {
                const er = document.createElement("div"); er.className = "sessRow";
                const et = document.createElement("div"); et.className = "sessTitle";
                et.style.color = "var(--muted)";
                et.textContent = "暂无会话, 点 + 新建";
                er.appendChild(et); rows.appendChild(er);
              }
              for (const t of sess) {
                const row = document.createElement("div");
                row.className = "sessRow";
                if (t.id === s.activeId) {
                  const d = document.createElement("span"); d.className = "dotCur";
                  row.appendChild(d);
                  row.style.background = "var(--userBg)";
                }
                const tt = document.createElement("div"); tt.className = "sessTitle";
                tt.textContent = t.title;
                const tm = document.createElement("div"); tm.className = "sessTime";
                tm.textContent = ago(t.updatedAt);
                const bd = document.createElement("span");
                bd.className = "sbadge " + (t.busy ? "run" : "done");
                bd.textContent = t.busy ? "⚡ 运行中" : "✓ 已完成";
                row.append(tt, tm, bd);
                row.addEventListener("click", () => selectThread(t.id));
                rows.appendChild(row);
              }
              card.appendChild(rows);
            }
            pc.appendChild(card);
          }
        }

        async function selectThread(id) {
          await fetch(BASE + "r/" + TOKEN + "/api/select", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ threadId: id })
          });
          lastJSON = "";
          showChat();
          refresh();
        }

        async function newSession(projectId) {
          await fetch(BASE + "r/" + TOKEN + "/api/new", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ projectId: projectId })
          });
          lastJSON = "";
          showChat();
          refresh();
        }

        function showChat() {
          inList = false;
          $("listPane").classList.add("hidden");
          $("chatPane").classList.remove("hidden");
        }

        function showList() {
          inList = true;
          $("chatPane").classList.add("hidden");
          $("listPane").classList.remove("hidden");
          renderProjects(lastState);
          window.scrollTo(0, 0);
        }

        async function refresh() {
          try {
            const r = await fetch(BASE + "r/" + TOKEN + "/api/state", { cache: "no-store" });
            if (!r.ok) {
              failuresCount += 1;
              if (failuresCount >= 2) showStuck(r.status);
              throw new Error(r.status);
            }
            failuresCount = 0;
            const text = await r.text();
            if (text === lastJSON) { $("dot").classList.remove("off"); return; }
            lastJSON = text;
            render(JSON.parse(text));
          } catch (e) {
            $("dot").classList.add("off");
            if (e instanceof TypeError) {
              failuresCount += 1;
              if (failuresCount >= 2) showStuck(0);
            }
          }
        }

        $("projChip").addEventListener("click", showList);
        $("backBtn").addEventListener("click", showChat);
        $("shieldBtn").addEventListener("click", () => switchTab(true));

        $("input").addEventListener("input", (ev) => {
          ev.target.style.height = "auto";
          ev.target.style.height = Math.min(140, ev.target.scrollHeight) + "px";
        });

        async function send() {
          const input = $("input");
          const text = input.value.trim();
          if (!text || busy) return;
          $("sendBtn").disabled = true;
          try {
            await fetch(BASE + "r/" + TOKEN + "/api/send", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ text: text })
            });
            input.value = "";
            input.style.height = "46px";
            lastJSON = "";
            await refresh();
          } finally {
            $("sendBtn").disabled = busy;
          }
        }
        $("sendBtn").addEventListener("click", send);
        $("input").addEventListener("keydown", (ev) => {
          if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); send(); }
        });
        // + = 上传图片附件 (选图 → base64 上传 Mac → 加入待发附件)。
        $("newBtn").addEventListener("click", () => $("fileInput").click());
        $("fileInput").addEventListener("change", async (ev) => {
          const files = [...(ev.target.files || [])];
          ev.target.value = "";
          if (!files.length) return;
          const row = $("attRow");
          for (let i = 0; i < files.length; i++) {
            row.classList.remove("hidden");
            row.classList.add("uploading");
            $("attMsg").textContent = "正在上传 " + (i + 1) + "/" + files.length + ": " + files[i].name;
            const dataUrl = await new Promise((resolve) => {
              const fr = new FileReader();
              fr.onload = () => resolve(String(fr.result || ""));
              fr.onerror = () => resolve("");
              fr.readAsDataURL(files[i]);
            });
            const base64 = dataUrl.split(",")[1] || "";
            if (!base64) continue;
            await fetch(BASE + "r/" + TOKEN + "/api/attach", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ name: files[i].name, data: base64 })
            });
          }
          row.classList.remove("uploading");
          $("attMsg").textContent = "";
          lastJSON = "";
          refresh();
        });

        // 模型选择面板 (列表来自 Mac 端 codex 配置)。
        function openModelSheet() {
          const list = $("modelList");
          list.textContent = "";
          const models = (lastState && lastState.model) ? [lastState.model] : [];
          if (!models.length) {
            const e = document.createElement("div"); e.className = "modelRow";
            e.textContent = "未获取到模型信息";
            list.appendChild(e);
          }
          for (const m of models) {
            const b = document.createElement("button");
            b.className = "modelRow" + (m === (lastState && lastState.model) ? " cur" : "");
            b.textContent = m;
            if (m === (lastState && lastState.model)) {
              const tag = document.createElement("span"); tag.className = "curTag";
              tag.textContent = "当前";
              b.appendChild(tag);
            }
            b.addEventListener("click", closeModelSheet);
            list.appendChild(b);
          }
          $("modelSheet").classList.remove("hidden");
        }
        function closeModelSheet() { $("modelSheet").classList.add("hidden"); }
        $("modelBtn").addEventListener("click", openModelSheet);
        $("sheetClose").addEventListener("click", closeModelSheet);
        $("modelSheet").addEventListener("click", (ev) => {
          if (ev.target === $("modelSheet")) closeModelSheet();
        });
        $("brainBtn").addEventListener("click", () => switchTab(true));

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
          $("chatPane").classList.toggle("hidden", toCtrl || inList);
          $("listPane").classList.toggle("hidden", toCtrl || !inList);
          $("ctrlPane").classList.toggle("hidden", !toCtrl);
          $("bar").classList.toggle("hidden", toCtrl);
        }
        $("tabChat").addEventListener("click", () => switchTab(false));
        $("tabCtrl").addEventListener("click", () => switchTab(true));

        async function ctrl(endpoint, body) {
          try {
            const r = await fetch(BASE + "r/" + TOKEN + "/api/ctrl/" + endpoint, {
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
            const r = await fetch(BASE + "r/" + TOKEN + "/api/ctrl/screen", { cache: "no-store" });
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
