import SwiftUI
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
    @State private var isLogoFloating = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 24) {
                Spacer()
                appIcon
                Text("Tapgo AICoding")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("仅限 Tapgo 管理员使用")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                qrCard
                    .frame(width: 320, height: 380)

                Spacer()
            }
            .padding(40)
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            isLogoFloating = true
            start()
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.98, blue: 0.99),
                Color(red: 0.90, green: 0.93, blue: 0.96),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var appIcon: some View {
        Image(systemName: "applescript")
            .font(.system(size: 64))
            .foregroundStyle(.blue)
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            .offset(y: isLogoFloating ? -8 : 0)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: isLogoFloating)
            .accessibilityHidden(true)
    }

    // MARK: - QR card

    @ViewBuilder
    private var qrCard: some View {
        VStack(spacing: 14) {
            switch phase {
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.regular)
                    Text("正在获取微信登录二维码…")
                        .font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    Button("重新获取二维码") { start() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)

            case .waiting:
                VStack(spacing: 12) {
                    ZStack(alignment: .center) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white)

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
                            .frame(width: 228, height: 228)
                            .opacity(isQRReady ? 1 : 0)
                            .accessibilityLabel("微信登录二维码")
                        }
                    }
                    .frame(width: 228, height: 228)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08)))
                    .padding(.top, 4)

                    Text("使用微信扫描二维码，确认后自动登录")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("等待扫码 · \(formattedRemaining)")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                    Button {
                        start()
                    } label: {
                        Label("刷新二维码", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.5)))
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 20)
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
            do {
                let config = try await authStore.client.fetchWechatLoginURL()
                guard !Task.isCancelled else { return }
                wechatLoginURL = config.url
                withAnimation(.easeInOut(duration: 0.2)) { phase = .waiting }
                try await poll(state: config.state)
            } catch is CancellationError {
                return
            } catch {
                withAnimation { phase = .failed(error.localizedDescription) }
            }
        }
    }

    @MainActor
    private func poll(state: String) async throws {
        let deadline = Date().addingTimeInterval(300)
        var tick = 0
        var consecutiveNetworkFailures = 0

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
                if consecutiveNetworkFailures < 3 { continue }
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
                '#tapgo-qr-root img{display:block!important;width:220px!important;height:220px!important;max-width:none!important;margin:0!important;padding:0!important;border:0!important;object-fit:contain!important;}';
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
