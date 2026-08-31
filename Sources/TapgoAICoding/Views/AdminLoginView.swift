import SwiftUI
import TapgoCore
import AppKit
import WebKit

/// Full-screen "scan to login" gate for Tapgo AICoding. Reuses the OctTapgo
/// admin **WeChat website QR login** (Path A): the app is only usable by a
/// Tapgo admin who scans the QR with WeChat and confirms on their phone.
///
/// The heavy lifting is a WKWebView that loads the `open.weixin.qq.com`
/// qrconnect URL returned by `login-url`, extracts the actual QR code image
/// (WeChat renders it lazily), then we poll `login-status` every 2s until the
/// scan is confirmed (token issued) or it times out.
struct AdminLoginView: View {
    @EnvironmentObject private var authStore: AdminAuthStore
    let onComplete: () -> Void

    enum Phase: Equatable {
        case loading
        case waiting
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var wechatLoginURL: URL?
    @State private var isQRReady = false
    @State private var secondsRemaining = 300
    @State private var task: Task<Void, Never>?
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private enum Layout {
        static let brandMinimumWidth: CGFloat = 430
        static let brandMaximumWidth: CGFloat = 560
        static let brandWidthRatio: CGFloat = 0.415
        static let qrSurfaceSize: CGFloat = 284
        static let qrContentSize: CGFloat = 260
    }

    var body: some View {
        GeometryReader { proxy in
            let brandWidth = min(
                max(proxy.size.width * Layout.brandWidthRatio, Layout.brandMinimumWidth),
                Layout.brandMaximumWidth
            )

            HStack(spacing: 0) {
                brandPanel
                    .frame(width: brandWidth)
                loginPanel
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(hex: 0xFBFAF8))
        .onAppear {
            start()
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Brand panel

    private var brandPanel: some View {
        ZStack {
            brandBackdrop

            VStack(spacing: 0) {
                Spacer(minLength: 96)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 200, height: 200)
                    .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 18)
                    .accessibilityLabel("Tapgo AICoding 应用图标")

                Text("Tapgo AICoding")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Text("安全连接你的 AI 工作空间")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 12)

                Spacer(minLength: 170)
            }
            .padding(.horizontal, 34)
            .multilineTextAlignment(.center)
            .offset(y: -64)
        }
        .clipped()
    }

    @ViewBuilder
    private var brandBackdrop: some View {
        if let url = Bundle.main.url(forResource: "LoginBrandBackground", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            Color(hex: 0x283893)
        }
    }

    // MARK: - Login panel

    private var loginPanel: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(hex: 0xFBFAF8)

                VStack(spacing: 0) {
                    Text("微信扫码登录")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color(hex: 0x17191D))
                    Text("仅限 Tapgo 管理员")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(hex: 0x777B82))
                        .padding(.top, 10)

                    loginState
                        .padding(.top, 28)
                }
                .frame(width: 420)
                .padding(.top, max(92, proxy.size.height * 0.15))
            }
            .overlay(alignment: .bottomTrailing) {
                footer
                    .padding(.trailing, 38)
                    .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private var loginState: some View {
        switch phase {
        case .loading:
            VStack(spacing: 18) {
                qrSurface {
                    ProgressView().controlSize(.large)
                }
                Text("正在获取微信登录二维码…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x777B82))
            }

        case .failed(let message):
            VStack(spacing: 18) {
                qrSurface {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(DSHTheme.warn)
                        Text(message)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .foregroundStyle(Color(hex: 0x4B4F56))
                            .frame(maxWidth: 190)
                    }
                }
                Button("重新获取二维码") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

        case .waiting:
            VStack(spacing: 0) {
                qrSurface {
                    ZStack {
                        if !isQRReady {
                            ProgressView().controlSize(.regular)
                        }
                        if let wechatLoginURL {
                            WechatLoginWebView(
                                url: wechatLoginURL,
                                onReady: {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        isQRReady = true
                                    }
                                },
                                onFailure: { message in
                                    withAnimation { phase = .failed(message) }
                                }
                            )
                            .frame(width: Layout.qrContentSize, height: Layout.qrContentSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .opacity(isQRReady ? 1 : 0)
                            .accessibilityLabel("微信登录二维码")
                        }
                    }
                }

                Text("打开微信扫一扫，确认后自动登录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x777B82))
                    .padding(.top, 22)

                HStack(spacing: 10) {
                    Circle()
                        .fill(DSHTheme.success)
                        .frame(width: 8, height: 8)
                    Text("等待扫码 · \(formattedRemaining)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x3B3E44))
                }
                .padding(.top, 18)

                Button { start() } label: {
                    Label("刷新二维码", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSHTheme.brand)
                .help("刷新二维码")
                .accessibilityLabel("刷新二维码")
                .padding(.top, 25)
            }
        }
    }

    private func qrSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: Layout.qrSurfaceSize, height: Layout.qrSurfaceSize)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private var footer: some View {
        Text("Tapgo 管理系统内部工具 · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0")")
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            .foregroundStyle(Color(hex: 0x858990))
    }

    private var formattedRemaining: String {
        String(
            format: "%d:%02d",
            CInt(max(secondsRemaining, 0) / 60),
            CInt(max(secondsRemaining, 0) % 60)
        )
    }

    // MARK: - Flow

    private func start() {
        task?.cancel()
        phase = .loading
        wechatLoginURL = nil
        isQRReady = false
        secondsRemaining = 300

        task = Task { @MainActor in
            // 最多重试 2 次（首次 + 1 次自动重试），只对瞬时网络错误生效；
            // 业务错误（401/配置不全等）直接交给失败页让用户手动处理。
            var attempt = 0
            let maxAttempts = 2
            var lastError: Error?

            while attempt < maxAttempts {
                attempt += 1
                do {
                    let config = try await authStore.client.fetchWechatLoginURL()
                    guard !Task.isCancelled else { return }
                    wechatLoginURL = config.url
                    withAnimation(.easeInOut(duration: 0.2)) { phase = .waiting }
                    try await poll(state: config.state)
                    return
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code != .cancelled {
                    lastError = error
                    if attempt < maxAttempts {
                        // 短暂等待再重试，给后端 / DNS 一个恢复窗口。
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        continue
                    }
                } catch {
                    lastError = error
                    break
                }
            }

            let message = lastError?.localizedDescription ?? "获取微信登录配置失败"
            withAnimation { phase = .failed(message) }
        }
    }

    @MainActor
    private func poll(state: String) async throws {
        let deadline = Date().addingTimeInterval(300)
        var tick = 0
        var consecutiveNetworkFailures = 0
        // 国内 → 海外服务器的链路偶尔抖一下（DNS / TLS / 跨运营商），
        // 2s × 6 = 12s 容错窗口再放弃，避免一次抖动就让用户看到失败页。
        let maxConsecutiveNetworkFailures = 6

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let remaining = max(Int(ceil(deadline.timeIntervalSinceNow)), 0)
            secondsRemaining = remaining
            tick += 1
            guard tick.isMultiple(of: 2) else { continue } // poll every 2s

            let status: AdminWechatStatus
            do {
                status = try await authStore.client.pollWechatLoginStatus(state: state)
                consecutiveNetworkFailures = 0
            } catch let error as URLError where error.code != .cancelled {
                consecutiveNetworkFailures += 1
                if consecutiveNetworkFailures < maxConsecutiveNetworkFailures { continue }
                throw error
            }

            switch status {
            case .confirmed(let token, let user):
                do {
                    try await authStore.completeLogin(token: token, user: user)
                    onComplete()
                } catch {
                    withAnimation { phase = .failed(error.localizedDescription) }
                }
                return
            case .needBind(let message):
                withAnimation { phase = .failed(message) }
                return
            case .expired:
                withAnimation { phase = .failed("微信二维码已过期，请重新扫码") }
                return
            case .waiting, .unknown:
                continue
            }
        }

        withAnimation { phase = .failed("微信二维码已过期，请重新扫码") }
    }
}

// MARK: - WKWebView QR renderer

/// Hosts the WeChat qrconnect page inside a non-persistent web view and, once
/// loaded, injects JS that (a) isolates the QR image and (b) tells the app
/// when it is ready / missing. Ported from OctTapgo's `admin-mac` LoginView.
private struct WechatLoginWebView: NSViewRepresentable {
    let url: URL
    let onReady: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "tapgoQrBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = 1
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapgoQrBridge")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedURL: URL?
        private let onReady: () -> Void
        private let onFailure: (String) -> Void

        init(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            let script = """
            (function() {
              if (window.__tapgoQrObserverInstalled) { return; }
              window.__tapgoQrObserverInstalled = true;
              var style = document.createElement('style');
              style.innerHTML =
                '*{box-sizing:border-box!important;}' +
                'html,body{width:100%!important;height:100%!important;margin:0!important;padding:0!important;overflow:hidden!important;background:#fff!important;}' +
                'body{display:flex!important;align-items:center!important;justify-content:center!important;}' +
                'body>:not(#tapgo-qr-root){visibility:hidden!important;position:absolute!important;pointer-events:none!important;}' +
                '#tapgo-qr-root{position:fixed!important;inset:0!important;display:flex!important;align-items:center!important;justify-content:center!important;background:#fff!important;z-index:2147483647!important;}' +
                '#tapgo-qr-root img{display:block!important;width:256px!important;height:256px!important;max-width:none!important;margin:0!important;padding:0!important;border:0!important;object-fit:contain!important;}';
              document.head.appendChild(style);

              function renderTapgoQRCode() {
                var source = document.querySelector('.web_qrcode_img, .impowerBox .qrcode img, .qrcode img');
                if (!source || !source.src) { return false; }
                var root = document.getElementById('tapgo-qr-root');
                if (!root) {
                  root = document.createElement('div');
                  root.id = 'tapgo-qr-root';
                  document.body.appendChild(root);
                }
                if (root.getAttribute('data-src') !== source.src) {
                  root.innerHTML = '';
                  var image = document.createElement('img');
                  image.src = source.src;
                  image.alt = '微信登录二维码';
                  root.appendChild(image);
                  root.setAttribute('data-src', source.src);
                }
                window.webkit.messageHandlers.tapgoQrBridge.postMessage('ready');
                return true;
              }

              if (!renderTapgoQRCode()) {
                var observer = new MutationObserver(function() {
                  if (renderTapgoQRCode()) { observer.disconnect(); }
                });
                observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
                window.setTimeout(function() {
                  if (!renderTapgoQRCode()) {
                    window.webkit.messageHandlers.tapgoQrBridge.postMessage('missing');
                  }
                }, 12000);
              }
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error { self?.reportFailure("二维码页面加载失败：\(error.localizedDescription)") }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            reportFailure("二维码页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            reportFailure("无法连接微信登录服务：\(error.localizedDescription)")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "tapgoQrBridge", let value = message.body as? String else { return }
            DispatchQueue.main.async { [weak self] in
                if value == "ready" {
                    self?.onReady()
                } else if value == "missing" {
                    self?.onFailure("未能读取微信二维码，请刷新后重试")
                }
            }
        }

        private func reportFailure(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onFailure(message)
            }
        }
    }
}
