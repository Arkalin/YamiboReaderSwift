import SwiftUI
import WebKit
import YamiboReaderCore

#if os(iOS)
import UIKit

@MainActor
public final class MangaWebFallbackModel: ObservableObject {
    @Published public private(set) var context: MangaWebContext
    @Published public private(set) var pageTitle = "网页漫画模式"
    @Published public private(set) var isLoading = false
    @Published public private(set) var showLoadError = false
    @Published public private(set) var canGoBack = false
    @Published public private(set) var showsReturnMask = false

    private weak var webView: WKWebView?
    private let appModel: YamiboAppModel
    private var initialLoadPrepared = false
    private var loadTimeoutTask: Task<Void, Never>?
    private var autoOpenTask: Task<Void, Never>?
    private var retryCount = 0

    public init(context: MangaWebContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
        self.showsReturnMask = context.waitingForNativeReturn
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        sync(with: webView)
    }

    func prepareAfterSessionApplied() {
        guard let webView else { return }

        if context.waitingForNativeReturn,
           webView.url?.absoluteString == context.currentURL.absoluteString,
           !webView.isLoading {
            sync(with: webView)
            resumeFromNativeReturn()
            return
        }

        guard !initialLoadPrepared else { return }
        initialLoadPrepared = true

        if webView.url?.absoluteString == context.currentURL.absoluteString,
           !webView.isLoading,
           !(webView.url?.absoluteString ?? "").isEmpty {
            sync(with: webView)
            installScriptsAndMaybeAutoOpen()
            return
        }

        startLoading(context.currentURL)
    }

    func retry() {
        guard let webView else { return }
        retryCount = 0
        showLoadError = false
        if let url = URL(string: context.currentURL.absoluteString), webView.url == nil {
            startLoading(url)
        } else {
            startLoading(context.currentURL)
        }
    }

    func close() {
        appModel.dismissManga()
    }

    func openOriginalPost() {
        appModel.dismissManga(openThreadInForum: context.originalThreadURL)
    }

    func goBackInWebView() {
        webView?.goBack()
    }

    func handlePageStarted(_ webView: WKWebView) {
        isLoading = true
        showLoadError = false
        sync(with: webView)
        installHideChromeScript(on: webView)
        scheduleLoadTimeout()
    }

    func handlePageVisible(_ webView: WKWebView) {
        loadTimeoutTask?.cancel()
        isLoading = false
        showLoadError = false
        sync(with: webView)
    }

    func handlePageFinished(_ webView: WKWebView) {
        loadTimeoutTask?.cancel()
        isLoading = false
        showLoadError = false
        sync(with: webView)
        installScriptsAndMaybeAutoOpen()
        if context.waitingForNativeReturn {
            resumeFromNativeReturn()
        }
    }

    func handlePageFailure(_ webView: WKWebView) {
        sync(with: webView)
        loadTimeoutTask?.cancel()
        isLoading = false
        if retryCount == 0 {
            retryCount = 1
            scheduleLoadTimeout()
            webView.reload()
        } else {
            showLoadError = true
        }
    }

    func handleNativeOpenRequest(title: String, clickedIndex: Int, urls: [URL]) {
        guard !urls.isEmpty else { return }
        autoOpenTask?.cancel()
        loadTimeoutTask?.cancel()
        context = context.updating(
            currentURL: webView?.url ?? context.currentURL,
            autoOpenNative: false,
            waitingForNativeReturn: false
        )
        let nativeContext = MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: context.currentURL,
            displayTitle: MangaTitleCleaner.cleanBookName(title.isEmpty ? pageTitle : title),
            source: context.source,
            initialPage: clickedIndex
        )
        appModel.presentMangaFromWeb(nativeContext, preserving: context)
    }

    private func startLoading(_ url: URL) {
        guard let webView else { return }
        autoOpenTask?.cancel()
        loadTimeoutTask?.cancel()
        isLoading = true
        showLoadError = false
        pageTitle = "网页漫画模式"
        context = context.updating(
            currentURL: url,
            waitingForNativeReturn: false
        )
        webView.load(URLRequest(url: url))
        scheduleLoadTimeout()
    }

    private func scheduleLoadTimeout() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, isLoading else { return }
            guard let webView else { return }
            if retryCount == 0 {
                retryCount = 1
                webView.stopLoading()
                webView.reload()
                scheduleLoadTimeout()
            } else {
                webView.stopLoading()
                isLoading = false
                showLoadError = true
            }
        }
    }

    private func installHideChromeScript(on webView: WKWebView) {
        Task {
            await webView.yamiboRunJavaScript(MangaWebJavaScript.hideChromeScript)
        }
    }

    private func installScriptsAndMaybeAutoOpen() {
        guard let webView else { return }
        Task {
            await webView.yamiboRunJavaScript(MangaWebJavaScript.hideChromeScript)
            await webView.yamiboRunJavaScript(MangaWebJavaScript.clickInterceptorScript)
        }
        triggerAutoOpenIfNeeded()
    }

    private func triggerAutoOpenIfNeeded() {
        guard context.autoOpenNative else { return }
        guard let webView else { return }

        autoOpenTask?.cancel()
        autoOpenTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if context.autoOpenNative {
                    context = context.updating(autoOpenNative: false)
                }
            }

            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if Task.isCancelled { return }
                if let payload = await webView.yamiboEvaluateExtractionPayload(
                    MangaWebJavaScript.extractionScript(includeHTML: false)
                ) {
                    if payload.isAnnouncement || (payload.sectionName != nil && !payload.isAllowedMangaPage) {
                        context = context.updating(autoOpenNative: false)
                        return
                    }

                    if !payload.urls.isEmpty {
                        handleNativeOpenRequest(
                            title: payload.title.isEmpty ? pageTitle : payload.title,
                            clickedIndex: context.initialPage,
                            urls: payload.urls
                        )
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            context = context.updating(autoOpenNative: false)
        }
    }

    private func sync(with webView: WKWebView) {
        canGoBack = webView.canGoBack
        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            pageTitle = title
        }
        if let url = webView.url {
            context = context.updating(currentURL: url)
        }
    }

    private func resumeFromNativeReturn() {
        showsReturnMask = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self else { return }
            context = context.updating(waitingForNativeReturn: false)
            showsReturnMask = false
        }
    }
}

public struct MangaWebFallbackView: View {
    @StateObject private var model: MangaWebFallbackModel
    private let appModel: YamiboAppModel

    public init(context: MangaWebContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: MangaWebFallbackModel(context: context, appModel: appModel))
        self.appModel = appModel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MangaFallbackWebView(model: model, appContext: appModel.appContext)

            if model.isLoading {
                overlayProgress
            } else if model.showLoadError {
                errorOverlay
            }

            if model.showsReturnMask {
                Color.black.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topChrome
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            if model.canGoBack {
                Button {
                    model.goBackInWebView()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
            }

            Text(model.pageTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("原帖") {
                model.openOriginalPost()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.black.opacity(0.82))
    }

    private var overlayProgress: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            ProgressView("正在载入网页漫画…")
                .tint(.white)
                .foregroundStyle(.white)
        }
    }

    private var errorOverlay: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text("网页漫画加载失败")
                    .foregroundStyle(.white)
                Button("重试") {
                    model.retry()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}

private struct MangaFallbackWebView: UIViewRepresentable {
    @ObservedObject var model: MangaWebFallbackModel
    let appContext: YamiboAppContext

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, appContext: appContext)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = MangaWebViewPool.shared.acquireVisibleWebView()
        context.coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach(webView)
        MangaWebViewPool.shared.releaseVisibleWebView(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: MangaWebFallbackModel
        private let appContext: YamiboAppContext
        private let bridge = MangaWebJSBridge()
        private weak var webView: WKWebView?

        init(model: MangaWebFallbackModel, appContext: YamiboAppContext) {
            self.model = model
            self.appContext = appContext
            super.init()
            bridge.onOpenNative = { [weak self] title, clickedIndex, urls in
                self?.model.handleNativeOpenRequest(
                    title: title,
                    clickedIndex: clickedIndex,
                    urls: urls
                )
            }
        }

        @MainActor
        func attach(_ webView: WKWebView) {
            guard self.webView !== webView else {
                model.attach(webView: webView)
                return
            }

            self.webView = webView
            webView.navigationDelegate = self
            webView.uiDelegate = self
            bridge.attach(to: webView)
            model.attach(webView: webView)

            Task { @MainActor in
                let sessionState = await appContext.sessionStore.load()
                await webView.yamiboApplySession(sessionState)
                model.prepareAfterSessionApplied()
            }
        }

        @MainActor
        func detach(_ webView: WKWebView) {
            bridge.detach(from: webView)
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.model.handlePageStarted(webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.model.handlePageVisible(webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.model.handlePageFinished(webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in
                self?.model.handlePageFailure(webView)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in
                self?.model.handlePageFailure(webView)
            }
        }

        nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor [weak self] in
                self?.model.handlePageFailure(webView)
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                if isInternal(url) {
                    webView.load(URLRequest(url: url))
                } else {
                    Task { @MainActor in
                        UIApplication.shared.open(url)
                    }
                }
            }
            return nil
        }

        private func isInternal(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "bbs.yamibo.com" || host.hasSuffix(".yamibo.com")
        }
    }
}
#else

public struct MangaWebFallbackView: View {
    private let context: MangaWebContext
    private let appModel: YamiboAppModel

    public init(context: MangaWebContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        Text("网页漫画模式仅在 iOS 端启用")
            .padding()
    }
}
#endif
