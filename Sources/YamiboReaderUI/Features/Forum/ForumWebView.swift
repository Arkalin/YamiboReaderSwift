import SwiftUI
import WebKit
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct IOSForumWebView: UIViewRepresentable {
    public let model: ForumBrowserModel
    public let sessionStore: SessionStore
    public let isSelected: Bool

    public init(model: ForumBrowserModel, sessionStore: SessionStore, isSelected: Bool = true) {
        self.model = model
        self.sessionStore = sessionStore
        self.isSelected = isSelected
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model, sessionStore: sessionStore)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(.yamiboHideChromeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        context.coordinator.applyAppearance(to: webView)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView)
        return webView
    }

    public func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.attach(view)
        context.coordinator.applyAppearance(to: view)
        if isSelected {
            context.coordinator.synchronizeCurrentSession(reloadIfNeeded: true)
        }
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: ForumBrowserModel
        private let sessionStore: SessionStore
        private weak var webView: WKWebView?
        private var didPrepareInitialLoad = false
        private var didApplyAppearance = false
        private var sessionObservationTask: Task<Void, Never>?
        private var sessionSyncState = ForumWebSessionSyncState()

        init(model: ForumBrowserModel, sessionStore: SessionStore) {
            self.model = model
            self.sessionStore = sessionStore
        }

        deinit {
            sessionObservationTask?.cancel()
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            model.attach(webView: webView)
            startObservingSessionChanges()

            guard !didPrepareInitialLoad else { return }
            didPrepareInitialLoad = true

            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                let sessionState = await sessionStore.load()
                await synchronizeWebViewSession(sessionState, reloadIfNeeded: false)
                if webView.url == nil {
                    model.load(model.currentURL ?? YamiboDomain.baseURL)
                }
            }
        }

        func applyAppearance(to webView: WKWebView) {
            let backgroundColor = YamiboColors.Site.creamBackgroundUIColor
            webView.overrideUserInterfaceStyle = .light
            webView.backgroundColor = backgroundColor
            webView.scrollView.backgroundColor = backgroundColor

            guard !didApplyAppearance else { return }
            didApplyAppearance = true
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(.yamiboHideChromeScript)
            webView.applyForumAppearance()
        }

        func synchronizeCurrentSession(reloadIfNeeded: Bool) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sessionState = await sessionStore.load()
                await synchronizeWebViewSession(sessionState, reloadIfNeeded: reloadIfNeeded)
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
            YamiboDomain.isYamiboHost(url)
        }

        private func startObservingSessionChanges() {
            guard sessionObservationTask == nil else { return }

            sessionObservationTask = Task { @MainActor [weak self] in
                for await notification in NotificationCenter.default.notifications(named: SessionStore.didChangeNotification) {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    guard let changeID = notification.userInfo?[SessionStore.changeIDUserInfoKey] as? String,
                          changeID == sessionStore.changeID else {
                        continue
                    }

                    let sessionState = await sessionStore.load()
                    await synchronizeWebViewSession(sessionState, reloadIfNeeded: true)
                }
            }
        }

        @MainActor
        private func synchronizeWebViewSession(_ sessionState: SessionState, reloadIfNeeded: Bool) async {
            guard let webView else { return }

            if let userAgent = sessionState.userAgent.nilIfEmpty,
               webView.customUserAgent != userAgent {
                webView.customUserAgent = userAgent
            }

            switch sessionSyncState.action(for: sessionState, reloadIfNeeded: reloadIfNeeded) {
            case .none:
                return
            case let .injectCookies(cookieHeader, reload):
                await injectCookies(cookieHeader, into: webView)
                if reload {
                    reloadOrLoad(webView)
                }
            case let .clearCookies(reload):
                await clearYamiboCookies(in: webView)
                if reload {
                    reloadOrLoad(webView)
                }
            }
        }

        @MainActor
        private func reloadOrLoad(_ webView: WKWebView) {
            if webView.url == nil {
                model.load(model.currentURL ?? YamiboDomain.baseURL)
            } else if let url = webView.url, isInternal(url) {
                webView.reload()
            }
        }

        private func injectCookies(_ cookieHeader: String, into webView: WKWebView) async {
            let cookies = cookieHeader
                .split(separator: ";")
                .compactMap { cookiePart -> HTTPCookie? in
                    let pair = cookiePart.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { return nil }
                    return HTTPCookie(properties: [
                        .domain: YamiboDomain.forumHost,
                        .path: "/",
                        .name: pair[0].trimmingCharacters(in: .whitespaces),
                        .value: pair[1].trimmingCharacters(in: .whitespaces),
                        .secure: "TRUE"
                    ])
                }

            await clearConflictingYamiboCookies(for: cookies, in: webView)
            for cookie in cookies {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookieAsync(cookie)
            }
        }

        private func clearConflictingYamiboCookies(for cookies: [HTTPCookie], in webView: WKWebView) async {
            let incomingNames = Set(cookies.map(\.name))
                .union([SessionState.authenticationCookieName])
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let storedCookies = await cookieStore.allCookies()
            for cookie in storedCookies
                where YamiboDomain.containsYamiboDomain(cookie.domain) &&
                incomingNames.contains(cookie.name) {
                await cookieStore.deleteCookieAsync(cookie)
            }
        }

        private func clearYamiboCookies(in webView: WKWebView) async {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where YamiboDomain.containsYamiboDomain(cookie.domain) {
                await cookieStore.deleteCookieAsync(cookie)
            }
        }

        private func persistCookies(from webView: WKWebView) async throws {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let header = cookies
                .filter { YamiboDomain.containsYamiboDomain($0.domain) }
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")

            let userAgent = webView.customUserAgent ?? YamiboNetworkConfiguration.defaultMobileUserAgent
            sessionSyncState.markPersistedWebSession(cookieHeader: header)
            try await sessionStore.updateWebSession(
                cookie: header,
                userAgent: userAgent,
                isLoggedIn: SessionState.hasAuthenticationCookie(header)
            )
        }
    }
}

private extension WKWebView {
    func applyForumAppearance() {
        evaluateJavaScript(WKUserScript.yamiboHideChromeSource)
    }
}

private extension WKUserScript {
    static let yamiboHideChromeScript = WKUserScript(
        source: yamiboHideChromeSource,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )

    static let yamiboHideChromeSource = """
        (function() {
            var style = document.getElementById('yamibo-hide-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'yamibo-hide-style';
                (document.head || document.documentElement).appendChild(style);
            }
            style.innerHTML = [
                "html,body{background:#FFF3D6 !important;color:#6E2B19 !important;}",
                "#wrap,.wrap,.wp,.ct2,.mn,.bm,.bm_c,.threadlist,.tl{background:#FFF3D6 !important;color:#6E2B19 !important;}",
                ".bm,.bm_c,.tl th,.tl td{border-color:rgba(109,58,43,0.18) !important;}",
                ".bm_h,.bm_h h2,.bm_h h3{background:#FFF7E0 !important;color:#6E2B19 !important;}",
                "a{color:#6E2B19 !important;}",
                ".foot.flex-box:not(.foot_reply){display:none !important;}",
                ".foot_height{display:none !important;}",
                ".my,.mz{visibility:hidden !important;pointer-events:none !important;}"
            ].join(" ");
        })();
        """
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

    func deleteCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            delete(cookie) {
                continuation.resume()
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
