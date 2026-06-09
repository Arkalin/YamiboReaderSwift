import SwiftUI
import WebKit
import YamiboReaderCore

#if os(macOS)
public struct ForumWebView: NSViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.load(URLRequest(url: url))
    }
}
#endif

#if os(iOS)
import UIKit

public struct IOSForumWebView: UIViewRepresentable {
    public let model: ForumBrowserModel
    public let appContext: YamiboAppContext

    public init(model: ForumBrowserModel, appContext: YamiboAppContext) {
        self.model = model
        self.appContext = appContext
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model, appContext: appContext)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(.yamiboHideChromeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView)
        return webView
    }

    public func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.attach(view)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: ForumBrowserModel
        private let appContext: YamiboAppContext
        private weak var webView: WKWebView?
        private var didPrepareInitialLoad = false

        init(model: ForumBrowserModel, appContext: YamiboAppContext) {
            self.model = model
            self.appContext = appContext
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            model.attach(webView: webView)

            guard !didPrepareInitialLoad else { return }
            didPrepareInitialLoad = true

            Task { @MainActor in
                let sessionState = await appContext.sessionStore.load()
                await injectCookies(sessionState.cookie, into: webView)
                if let userAgent = sessionState.userAgent.nilIfEmpty {
                    webView.customUserAgent = userAgent
                }
                if webView.url == nil {
                    model.load(model.currentURL ?? YamiboRoute.baseURL)
                }
            }
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.sync(with: webView)
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.sync(with: webView)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.sync(with: webView)
            if let url = webView.url {
                model.recordVisit(url: url, title: webView.title)
            }
            Task {
                try? await persistCookies(from: webView)
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            model.sync(with: webView)
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            model.sync(with: webView)
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil, isInternal(url) {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }

            if !isInternal(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                if isInternal(url) {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        private func isInternal(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "bbs.yamibo.com" || host.hasSuffix(".yamibo.com")
        }

        private func injectCookies(_ cookieHeader: String, into webView: WKWebView) async {
            let cookies = cookieHeader
                .split(separator: ";")
                .compactMap { cookiePart -> HTTPCookie? in
                    let pair = cookiePart.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { return nil }
                    return HTTPCookie(properties: [
                        .domain: "bbs.yamibo.com",
                        .path: "/",
                        .name: pair[0].trimmingCharacters(in: .whitespaces),
                        .value: pair[1].trimmingCharacters(in: .whitespaces),
                        .secure: "TRUE"
                    ])
                }

            for cookie in cookies {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookieAsync(cookie)
            }
        }

        private func persistCookies(from webView: WKWebView) async throws {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let header = cookies
                .filter { $0.domain.contains("yamibo.com") }
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")

            let userAgent = webView.customUserAgent ?? YamiboDefaults.defaultMobileUserAgent
            try await appContext.sessionStore.updateWebSession(
                cookie: header,
                userAgent: userAgent,
                isLoggedIn: !header.isEmpty
            )
        }
    }
}

private extension WKUserScript {
    static let yamiboHideChromeScript = WKUserScript(
        source: """
        (function() {
            var style = document.getElementById('yamibo-hide-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'yamibo-hide-style';
                (document.head || document.documentElement).appendChild(style);
            }
            style.innerHTML = ".foot.flex-box:not(.foot_reply){display:none !important;} .foot_height{display:none !important;} .my,.mz{visibility:hidden !important;pointer-events:none !important;}";
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )
}

private extension WKHTTPCookieStore {
    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
