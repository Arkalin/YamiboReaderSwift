import Foundation
import YamiboReaderCore

#if os(iOS)
import ObjectiveC
import WebKit

public struct MangaProbeService {
    private let appContext: YamiboAppContext

    public init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    @MainActor
    public func probe(
        launchContext: MangaLaunchContext,
        currentHTML: String?,
        currentTitle: String?
    ) async -> MangaProbeOutcome {
        if let currentHTML {
            let immediateOutcome = Self.immediateOutcome(
                launchContext: launchContext,
                html: currentHTML,
                title: currentTitle
            )
            switch immediateOutcome {
            case .success:
                return immediateOutcome
            case let .fallback(reason, _):
                if reason == .notManga {
                    return immediateOutcome
                }
            }
        }

        return await probeWithHiddenWebView(
            launchContext: launchContext,
            fallbackTitle: currentTitle
        )
    }

    static func immediateOutcome(
        launchContext: MangaLaunchContext,
        html: String,
        title: String?
    ) -> MangaProbeOutcome {
        let webContext = makeSuggestedWebContext(from: launchContext)
        if MangaHTMLParser.isAnnouncement(from: html) {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        let sectionName = MangaHTMLParser.extractSectionName(from: html)
        if let sectionName, !MangaHTMLParser.isAllowedMangaSection(sectionName) {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        guard MangaHTMLParser.isLikelyMangaThread(title: title, html: html) else {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        let images = MangaHTMLParser.extractImageURLs(from: html, baseURL: launchContext.chapterURL)
        guard !images.isEmpty else {
            return .fallback(reason: .noImages, suggestedWebContext: webContext)
        }

        let resolvedTitle = MangaHTMLParser.extractThreadTitle(from: html) ?? title ?? launchContext.displayTitle
        return .success(
            MangaProbePayload(
                images: images,
                title: resolvedTitle,
                html: html,
                sectionName: sectionName
            )
        )
    }

    static func makeSuggestedWebContext(from launchContext: MangaLaunchContext) -> MangaWebContext {
        MangaWebContext(
            currentURL: launchContext.chapterURL,
            originalThreadURL: launchContext.originalThreadURL,
            source: launchContext.source,
            initialPage: launchContext.initialPage,
            autoOpenNative: true,
            waitingForNativeReturn: false
        )
    }

    static func failureReason(for error: Error) -> MangaProbeFailureReason {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .retryableNetwork
        }
        return .timeout
    }

    @MainActor
    private func probeWithHiddenWebView(
        launchContext: MangaLaunchContext,
        fallbackTitle: String?
    ) async -> MangaProbeOutcome {
        let webContext = Self.makeSuggestedWebContext(from: launchContext)
        let lease = MangaWebViewPool.shared.acquireProbeWebView()
        let webView = lease.webView
        let sessionState = await appContext.sessionStore.load()
        await webView.yamiboApplySession(sessionState)

        return await withCheckedContinuation { continuation in
            let delegate = HiddenProbeNavigationDelegate(
                webView: webView,
                launchContext: launchContext,
                fallbackTitle: fallbackTitle
            ) { outcome in
                continuation.resume(returning: outcome)
            }
            webView.navigationDelegate = delegate
            webView.uiDelegate = delegate
            objc_setAssociatedObject(
                webView,
                HiddenProbeAssociationKey,
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            delegate.begin()
            webView.load(URLRequest(url: webContext.currentURL))
        }.also { _ in
            objc_setAssociatedObject(
                webView,
                HiddenProbeAssociationKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            MangaWebViewPool.shared.releaseProbeWebView(webView, isPooled: lease.isPooled)
        }
    }
}

@MainActor
private let HiddenProbeAssociationKey = UnsafeRawPointer(
    UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
)

private final class HiddenProbeNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let launchContext: MangaLaunchContext
    private let fallbackTitle: String?
    private let completion: (MangaProbeOutcome) -> Void

    private var didComplete = false
    private var retryIndex = 0
    private var softDeadline = Date().addingTimeInterval(12)
    private let hardDeadline = Date().addingTimeInterval(18)
    private var timeoutTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    init(
        webView: WKWebView,
        launchContext: MangaLaunchContext,
        fallbackTitle: String?,
        completion: @escaping (MangaProbeOutcome) -> Void
    ) {
        self.webView = webView
        self.launchContext = launchContext
        self.fallbackTitle = fallbackTitle
        self.completion = completion
    }

    @MainActor
    func begin() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if Date() >= hardDeadline || Date() >= softDeadline {
                    complete(
                        .fallback(
                            reason: .timeout,
                            suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: launchContext)
                        )
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            self.handleDidFinish(webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.handleFailure(error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.handleFailure(error)
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.complete(
                .fallback(
                    reason: .webProcessTerminated,
                    suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: self.launchContext)
                )
            )
        }
    }

    @MainActor
    private func handleDidFinish(_ webView: WKWebView) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0 ..< 10 {
                if Task.isCancelled { return }

                if let payload = await webView.yamiboEvaluateExtractionPayload(
                    MangaWebJavaScript.extractionScript(includeHTML: true)
                ) {
                    if payload.isAnnouncement || (payload.sectionName != nil && !payload.isAllowedMangaPage) {
                        complete(
                            .fallback(
                                reason: .notManga,
                                suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: launchContext)
                            )
                        )
                        return
                    }

                    if !payload.urls.isEmpty {
                        complete(
                            .success(
                                MangaProbePayload(
                                    images: payload.urls,
                                    title: payload.title.isEmpty ? (fallbackTitle ?? launchContext.displayTitle) : payload.title,
                                    html: payload.html,
                                    sectionName: payload.sectionName
                                )
                            )
                        )
                        return
                    }
                }

                if attempt < 9 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }

            complete(
                .fallback(
                    reason: .noImages,
                    suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: launchContext)
                )
            )
        }
    }

    @MainActor
    private func handleFailure(_ error: Error) {
        let reason = MangaProbeService.failureReason(for: error)
        guard reason == .retryableNetwork, retryIndex < 2 else {
            complete(
                .fallback(
                    reason: reason,
                    suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: launchContext)
                )
            )
            return
        }

        let backoff: TimeInterval = retryIndex == 0 ? 1.5 : 3
        retryIndex += 1
        softDeadline = min(hardDeadline, softDeadline.addingTimeInterval(backoff))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard let self, !didComplete else { return }
            webView.reload()
        }
    }

    @MainActor
    private func complete(_ outcome: MangaProbeOutcome) {
        guard !didComplete else { return }
        didComplete = true
        timeoutTask?.cancel()
        pollingTask?.cancel()
        completion(outcome)
    }
}

private extension MangaProbeOutcome {
    func also(_ sideEffect: (MangaProbeOutcome) -> Void) -> MangaProbeOutcome {
        sideEffect(self)
        return self
    }
}
#else

public struct MangaProbeService {
    public init(appContext: YamiboAppContext) {}

    public func probe(
        launchContext: MangaLaunchContext,
        currentHTML: String?,
        currentTitle: String?
    ) async -> MangaProbeOutcome {
        if let currentHTML {
            return Self.immediateOutcome(
                launchContext: launchContext,
                html: currentHTML,
                title: currentTitle
            )
        }

        return .fallback(
            reason: .timeout,
            suggestedWebContext: Self.makeSuggestedWebContext(from: launchContext)
        )
    }

    static func immediateOutcome(
        launchContext: MangaLaunchContext,
        html: String,
        title: String?
    ) -> MangaProbeOutcome {
        let webContext = makeSuggestedWebContext(from: launchContext)
        if MangaHTMLParser.isAnnouncement(from: html) {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        let sectionName = MangaHTMLParser.extractSectionName(from: html)
        if let sectionName, !MangaHTMLParser.isAllowedMangaSection(sectionName) {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        guard MangaHTMLParser.isLikelyMangaThread(title: title, html: html) else {
            return .fallback(reason: .notManga, suggestedWebContext: webContext)
        }

        let images = MangaHTMLParser.extractImageURLs(from: html, baseURL: launchContext.chapterURL)
        guard !images.isEmpty else {
            return .fallback(reason: .noImages, suggestedWebContext: webContext)
        }

        let resolvedTitle = MangaHTMLParser.extractThreadTitle(from: html) ?? title ?? launchContext.displayTitle
        return .success(
            MangaProbePayload(
                images: images,
                title: resolvedTitle,
                html: html,
                sectionName: sectionName
            )
        )
    }

    static func makeSuggestedWebContext(from launchContext: MangaLaunchContext) -> MangaWebContext {
        MangaWebContext(
            currentURL: launchContext.chapterURL,
            originalThreadURL: launchContext.originalThreadURL,
            source: launchContext.source,
            initialPage: launchContext.initialPage,
            autoOpenNative: true,
            waitingForNativeReturn: false
        )
    }

    static func failureReason(for error: Error) -> MangaProbeFailureReason {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .retryableNetwork
        }
        return .timeout
    }
}
#endif
