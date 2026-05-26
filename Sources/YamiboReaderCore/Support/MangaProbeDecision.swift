import Foundation

public struct MangaProbeSnapshot: Equatable, Sendable {
    public var title: String?
    public var html: String?
    public var sectionName: String?
    public var isAnnouncement: Bool
    public var imageURLs: [URL]
    public var baseURL: URL

    public init(
        title: String?,
        html: String?,
        sectionName: String?,
        isAnnouncement: Bool,
        imageURLs: [URL],
        baseURL: URL
    ) {
        self.title = title
        self.html = html
        self.sectionName = sectionName
        self.isAnnouncement = isAnnouncement
        self.imageURLs = imageURLs
        self.baseURL = baseURL
    }

    public init(html: String, title: String?, fallbackTitle: String, baseURL: URL) {
        self.html = html
        self.sectionName = MangaHTMLParser.extractSectionName(from: html)
        self.isAnnouncement = MangaHTMLParser.isAnnouncement(from: html)
        self.imageURLs = MangaHTMLParser.extractImageURLs(from: html, baseURL: baseURL)
        self.baseURL = baseURL
        self.title = MangaHTMLParser.extractThreadTitle(from: html) ?? title ?? fallbackTitle
    }
}

public enum MangaProbeClassification: Equatable, Sendable {
    case success(MangaProbePayload)
    case notManga
    case noImages
}

public enum MangaProbeDecision {
    public static func classify(_ snapshot: MangaProbeSnapshot) -> MangaProbeClassification {
        if snapshot.isAnnouncement {
            return .notManga
        }

        if let sectionName = snapshot.sectionName,
           !MangaHTMLParser.isAllowedMangaSection(sectionName) {
            return .notManga
        }

        if let html = snapshot.html,
           !MangaHTMLParser.isLikelyMangaThread(title: snapshot.title, html: html) {
            return .notManga
        }

        guard !snapshot.imageURLs.isEmpty else {
            return .noImages
        }

        return .success(
            MangaProbePayload(
                images: snapshot.imageURLs,
                title: snapshot.title ?? "",
                html: snapshot.html,
                sectionName: snapshot.sectionName
            )
        )
    }

    public static func immediateOutcome(
        launchContext: MangaLaunchContext,
        html: String,
        title: String?
    ) -> MangaProbeOutcome {
        outcome(
            for: classify(
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

    public static func shouldCompleteAfterImmediateOutcome(_ outcome: MangaProbeOutcome) -> Bool {
        switch outcome {
        case .success:
            return true
        case let .fallback(reason, _):
            return reason == .notManga
        }
    }

    public static func suggestedWebContext(from launchContext: MangaLaunchContext) -> MangaWebContext {
        MangaWebContext(
            currentURL: launchContext.chapterURL,
            originalThreadURL: launchContext.originalThreadURL,
            source: launchContext.source,
            initialPage: launchContext.initialPage,
            autoOpenNative: true,
            waitingForNativeReturn: false
        )
    }

    public static func failureReason(for error: Error) -> MangaProbeFailureReason {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .retryableNetwork
        }
        return .timeout
    }

    public static func outcome(
        for classification: MangaProbeClassification,
        launchContext: MangaLaunchContext
    ) -> MangaProbeOutcome {
        switch classification {
        case let .success(payload):
            return .success(payload)
        case .notManga:
            return .fallback(
                reason: .notManga,
                suggestedWebContext: suggestedWebContext(from: launchContext)
            )
        case .noImages:
            return .fallback(
                reason: .noImages,
                suggestedWebContext: suggestedWebContext(from: launchContext)
            )
        }
    }
}
