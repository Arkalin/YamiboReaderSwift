import Foundation
import YamiboReaderCore

#if os(iOS)
import ObjectiveC
import WebKit

public struct MangaProbeService {
    private let appContext: YamiboAppContext
    private let dynamicProbe: @MainActor (MangaLaunchContext, String?) async -> MangaProbeOutcome

    public init(appContext: YamiboAppContext) {
        self.init(appContext: appContext, dynamicProbe: nil)
    }

    init(
        appContext: YamiboAppContext,
        dynamicProbe: (@MainActor (MangaLaunchContext, String?) async -> MangaProbeOutcome)?
    ) {
        self.appContext = appContext
        self.dynamicProbe = dynamicProbe ?? { [appContext] launchContext, fallbackTitle in
            await Self.probeWithHiddenWebView(
                appContext: appContext,
                launchContext: launchContext,
                fallbackTitle: fallbackTitle
            )
        }
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
            if Self.shouldCompleteAfterImmediateOutcome(immediateOutcome) {
                return immediateOutcome
            }
        }

        return await dynamicProbe(launchContext, currentTitle)
    }

    static func immediateOutcome(
        launchContext: MangaLaunchContext,
        html: String,
        title: String?
    ) -> MangaProbeOutcome {
        outcome(
            for: MangaProbeClassifier.classify(
                MangaProbeSnapshot(
                    html: html,
                    title: title,
                    fallbackTitle: launchContext.displayTitle,
                    baseURL: launchContext.chapterURL
                )
            ),
            launchContext: launchContext
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
    private static func probeWithHiddenWebView(
        appContext: YamiboAppContext,
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
                    let classification = MangaProbeClassifier.classify(
                        MangaProbeSnapshot(
                            title: payload.title.isEmpty ? (fallbackTitle ?? launchContext.displayTitle) : payload.title,
                            html: payload.html,
                            sectionName: payload.sectionName,
                            isAnnouncement: payload.isAnnouncement,
                            imageURLs: payload.urls,
                            baseURL: launchContext.chapterURL
                        )
                    )

                    switch classification {
                    case .notManga:
                        complete(
                            .fallback(
                                reason: .notManga,
                                suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: launchContext)
                            )
                        )
                        return
                    case let .success(payload):
                        complete(.success(payload))
                        return
                    case .noImages:
                        break
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
    private let dynamicProbe: @MainActor (MangaLaunchContext, String?) async -> MangaProbeOutcome
    private let usesInjectedDynamicProbe: Bool

    public init(appContext: YamiboAppContext) {
        self.init(appContext: appContext, dynamicProbe: nil)
    }

    init(
        appContext _: YamiboAppContext,
        dynamicProbe: (@MainActor (MangaLaunchContext, String?) async -> MangaProbeOutcome)?
    ) {
        usesInjectedDynamicProbe = dynamicProbe != nil
        self.dynamicProbe = dynamicProbe ?? { launchContext, _ in
            .fallback(
                reason: .timeout,
                suggestedWebContext: Self.makeSuggestedWebContext(from: launchContext)
            )
        }
    }

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
            if usesInjectedDynamicProbe, !Self.shouldCompleteAfterImmediateOutcome(immediateOutcome) {
                return await dynamicProbe(launchContext, currentTitle)
            }
            return immediateOutcome
        }

        return await dynamicProbe(launchContext, currentTitle)
    }

    static func immediateOutcome(
        launchContext: MangaLaunchContext,
        html: String,
        title: String?
    ) -> MangaProbeOutcome {
        outcome(
            for: MangaProbeClassifier.classify(
                MangaProbeSnapshot(
                    html: html,
                    title: title,
                    fallbackTitle: launchContext.displayTitle,
                    baseURL: launchContext.chapterURL
                )
            ),
            launchContext: launchContext
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

extension MangaProbeService {
    static func shouldCompleteAfterImmediateOutcome(_ outcome: MangaProbeOutcome) -> Bool {
        switch outcome {
        case .success:
            return true
        case let .fallback(reason, _):
            return reason == .notManga
        }
    }

    static func outcome(
        for classification: MangaProbeClassification,
        launchContext: MangaLaunchContext
    ) -> MangaProbeOutcome {
        switch classification {
        case let .success(payload):
            return .success(payload)
        case .notManga:
            return .fallback(
                reason: .notManga,
                suggestedWebContext: makeSuggestedWebContext(from: launchContext)
            )
        case .noImages:
            return .fallback(
                reason: .noImages,
                suggestedWebContext: makeSuggestedWebContext(from: launchContext)
            )
        }
    }
}
