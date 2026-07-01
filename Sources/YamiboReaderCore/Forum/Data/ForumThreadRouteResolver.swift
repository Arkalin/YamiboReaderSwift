import Foundation

public actor ForumThreadRouteResolver {
    private let client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func resolve(_ request: ThreadRouteRequest) async throws -> ThreadRouteTarget {
        let requestURL = URL(string: request.threadURL.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL
            ?? request.threadURL.absoluteURL
        let canonicalURL = canonicalThreadURL(from: requestURL) ?? requestURL
        let initialFid = request.tapContext.containingFid ?? request.threadFid
        let initialKind = kindForKnownInputs(
            fid: initialFid,
            knownThreadKind: request.knownThreadKind,
            title: nil
        )

        let metadata: ThreadMetadata?
        if shouldFetchMetadata(fid: initialFid, knownThreadKind: request.knownThreadKind) {
            do {
                metadata = try await loadMetadata(for: requestURL)
            } catch let fallback as ForumThreadRouteResolverWebFallback {
                return .webFallback(fallback.url)
            }
        } else {
            metadata = nil
        }

        let tid = request.threadID
            ?? metadata?.tid
            ?? threadID(from: canonicalURL)
            ?? MangaTitleCleaner.extractTid(from: canonicalURL.absoluteString)
            ?? ""
        let fid = initialFid ?? metadata?.fid
        let title = request.title ?? metadata?.title
        let authorID = request.authorID ?? metadata?.authorID
        let targetPostID = request.targetPostID ?? postID(from: requestURL)
        let thread = ThreadIdentity(tid: tid, canonicalURL: canonicalURL, fid: fid)
        let baseInitialPage = pageNumber(from: requestURL) ?? pageNumber(from: canonicalURL) ?? 1
        let kind = metadata == nil
            ? initialKind
            : kindForKnownInputs(
                fid: fid,
                knownThreadKind: request.knownThreadKind,
                title: [title, metadata?.sectionText].compactMap { $0 }.joined(separator: " ")
            )

        switch kind {
        case .novel:
            return .novelDetail(
                NovelDetailLaunchContext(
                    thread: thread,
                    title: title ?? L10n.string("reader.title"),
                    authorID: authorID
                )
            )
        case .manga:
            let rawTitle = title ?? L10n.string("manga.reader.title")
            let cleanBookName = MangaTitleCleaner.cleanBookName(rawTitle)
            return .mangaDetail(
                MangaDetailLaunchContext(
                    thread: thread,
                    title: cleanBookName,
                    focusedChapterTID: tid,
                    directoryNameHint: cleanBookName
                )
            )
        case .regular, .unknown:
            let initialPage = try await resolvedThreadReaderInitialPage(
                requestURL: requestURL,
                baseInitialPage: baseInitialPage,
                thread: thread,
                title: title
            )
            return .threadReader(
                ThreadReaderLaunchContext(
                    thread: thread,
                    title: title ?? L10n.string("forum.default_title"),
                    initialPage: initialPage,
                    targetPostID: targetPostID,
                    authorID: authorID
                )
            )
        }
    }

    private func shouldFetchMetadata(fid: String?, knownThreadKind: YamiboForumThreadKind?) -> Bool {
        if let fid, YamiboForumTaxonomy.threadKind(for: fid) != .unknown {
            return false
        }
        if let knownThreadKind, knownThreadKind != .unknown {
            return false
        }
        return fid == nil
    }

    private func loadMetadata(for url: URL) async throws -> ThreadMetadata {
        do {
            let html = try await client.fetchHTML(for: .thread(url: url, page: 1, authorID: nil))
            return try ThreadMetadataHTMLParser.parse(from: html, url: url)
        } catch YamiboError.notAuthenticated {
            throw ForumThreadRouteResolverWebFallback(url: url)
        } catch YamiboError.floodControl {
            throw ForumThreadRouteResolverWebFallback(url: url)
        }
    }

    private func kindForKnownInputs(
        fid: String?,
        knownThreadKind: YamiboForumThreadKind?,
        title: String?
    ) -> YamiboForumThreadKind {
        if let fid {
            let taxonomyKind = YamiboForumTaxonomy.threadKind(for: fid)
            if taxonomyKind != .unknown {
                return taxonomyKind
            }
            if let knownThreadKind, knownThreadKind != .unknown {
                return knownThreadKind
            }
            return .regular
        }

        if let knownThreadKind, knownThreadKind != .unknown {
            return knownThreadKind
        }

        if isNovelMarker(title) {
            return .novel
        }

        return .regular
    }

    private func isNovelMarker(_ value: String?) -> Bool {
        guard let value else { return false }
        let markers = ["文學區", "文学区", "原创小说区", "原創小說區", "轻小说/译文区", "輕小說/譯文區", "TXT小说区", "TXT小說區"]
        return markers.contains { value.localizedCaseInsensitiveContains($0) }
    }

    private func canonicalThreadURL(from url: URL) -> URL? {
        if url.host == nil {
            return YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url)
        }
        if url.host?.contains("yamibo.com") == true {
            return YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url)
        }
        return nil
    }

    private func isFindPostURL(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return url.absoluteString.localizedCaseInsensitiveContains("findpost")
        }
        return items.value(named: "goto") == "findpost"
            || (items.value(named: "mod") == "redirect" && items.value(named: "pid") != nil)
    }

    private func threadID(from url: URL) -> String? {
        YamiboThreadURLCanonicalizer.threadID(from: url)
    }

    private func postID(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pid" })?
            .value?
            .threadRoutingTrimmedNonEmpty
    }

    private func pageNumber(from url: URL) -> Int? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value
            .flatMap(Int.init),
           value > 0 {
            return value
        }

        return HTMLTextExtractor.firstMatch(pattern: #"thread-\d+-(\d+)-\d+\.html"#, in: url.absoluteString)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private func resolvedThreadReaderInitialPage(
        requestURL: URL,
        baseInitialPage: Int,
        thread: ThreadIdentity,
        title: String?
    ) async throws -> Int {
        guard baseInitialPage <= 1, isFindPostURL(requestURL) else {
            return baseInitialPage
        }

        let html = try await client.fetchHTML(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let page = try ForumThreadPageHTMLParser.parsePage(
            from: html,
            thread: thread,
            fallbackTitle: title
        )
        return page.pageNavigation?.currentPage ?? baseInitialPage
    }
}

private struct ForumThreadRouteResolverWebFallback: Error {
    var url: URL
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}
