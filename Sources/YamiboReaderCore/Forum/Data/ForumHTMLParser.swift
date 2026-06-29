import Foundation
import SwiftSoup

public enum ForumHTMLParser {
    public static func parseHomePage(from html: String, fetchedAt: Date = .now) throws -> ForumHomePage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let categories = parseCategories(in: document)
        guard categories.contains(where: { !$0.boards.isEmpty }) else {
            throw YamiboError.parsingFailed(context: L10n.string("context.forum_home"))
        }

        return ForumHomePage(
            categories: categories,
            carouselItems: parseCarouselItems(in: document),
            formHash: parseFormHash(in: document, html: html),
            fetchedAt: fetchedAt
        )
    }

    public static func parseBoardPage(
        from html: String,
        fid: String,
        title: String? = nil,
        fetchedAt: Date = .now
    ) throws -> ForumBoardPage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let documentTitle = (try? document.select("title").first()?.text())?
            .replacingOccurrences(of: " -  百合会.*", with: "", options: .regularExpression)
        let resolvedTitle = title?.nilIfBlank ?? documentTitle
        let board = ForumBoardSummary(
            fid: fid,
            name: resolvedTitle?.nilIfBlank ?? L10n.string("forum.board"),
            url: ForumRouteResolver.boardURL(fid: fid)
        )
        return ForumBoardPage(
            board: board,
            threads: parseThreadSummaries(in: document),
            pageNavigation: ForumPageNavigation(currentPage: 1),
            formHash: parseFormHash(in: document, html: html),
            fetchedAt: fetchedAt
        )
    }

    private static func parseCategories(in document: Document) -> [ForumCategory] {
        let headers = (try? document.select(".forumlist .subforumshow")) ?? Elements()
        var categories: [ForumCategory] = []
        var seenCategoryIDs = Set<String>()

        for (index, header) in headers.array().enumerated() {
            let targetSelector = ((try? header.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((try? header.select("h2").text()) ?? (try? header.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let rawID = targetSelector
                .replacingOccurrences(of: "#", with: "")
                .nilIfBlank ?? "category-\(index)"
            let boardsContainer = targetSelector.isEmpty ? nil : try? document.select(targetSelector).first()
            let boards = boardsContainer.map(parseBoards(in:)) ?? []
            guard !boards.isEmpty else { continue }

            let uniqueID = uniqueIdentifier(rawID, seen: &seenCategoryIDs)
            categories.append(ForumCategory(id: uniqueID, title: title, boards: boards))
        }

        return categories
    }

    private static func parseBoards(in container: Element) -> [ForumBoardSummary] {
        let rows = (try? container.select("li")) ?? Elements()
        var boards: [ForumBoardSummary] = []
        var seenFIDs = Set<String>()

        for row in rows {
            guard let link = ((try? row.select("a.murl[href*='fid=']").first()) ?? (try? row.select("a[href*='mod=forumdisplay'][href*='fid=']").first())),
                  let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let fid = forumID(from: url),
                  seenFIDs.insert(fid).inserted else {
                continue
            }

            let titleElement = try? link.select(".mtit").first()
            let todayText = ((try? titleElement?.select(".mnum").text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var name = ((try? titleElement?.text()) ?? (try? link.text()) ?? "")
                .replacingOccurrences(of: todayText, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                name = ((try? row.select("img[alt]").first()?.attr("alt")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !name.isEmpty else { continue }

            let detail = ((try? link.select(".mtxt").text()) ?? "").nilIfBlank
            let iconHref = (try? row.select("img[src]").first()?.attr("src")) ?? ""
            boards.append(
                ForumBoardSummary(
                    fid: fid,
                    name: name,
                    detail: detail,
                    todayCount: todayCount(from: todayText),
                    iconURL: HTMLTextExtractor.absoluteURL(from: iconHref),
                    url: url
                )
            )
        }

        return boards
    }

    private static func parseCarouselItems(in document: Document) -> [ForumHomeCarouselItem] {
        let slides = (try? document.select(".yami-swiper .swiper-slide a[href]")) ?? Elements()
        var items: [ForumHomeCarouselItem] = []
        var seen = Set<String>()

        for slide in slides {
            let href = (try? slide.attr("href")) ?? ""
            guard let targetURL = HTMLTextExtractor.absoluteURL(from: href),
                  let image = try? slide.select("img[src]").first(),
                  let imageURL = HTMLTextExtractor.absoluteURL(from: (try? image.attr("src")) ?? "") else {
                continue
            }
            let item = ForumHomeCarouselItem(
                targetURL: targetURL,
                imageURL: imageURL,
                threadID: threadID(from: targetURL)
            )
            guard seen.insert(item.id).inserted else { continue }
            items.append(item)
        }

        return items
    }

    private static func parseThreadSummaries(in document: Document) -> [ForumThreadSummary] {
        let links = (try? document.select("a[href*='viewthread'][href*='tid='], a[href*='thread-']")) ?? Elements()
        var summaries: [ForumThreadSummary] = []
        var seen = Set<String>()

        for link in links {
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let tid = threadID(from: url),
                  seen.insert(tid).inserted else {
                continue
            }
            summaries.append(ForumThreadSummary(tid: tid, title: title, url: url))
        }

        return summaries
    }

    private static func parseFormHash(in document: Document, html: String) -> String? {
        if let value = try? document.select("input[name=formhash]").first()?.attr("value"),
           let normalized = value.nilIfBlank {
            return normalized
        }

        return HTMLTextExtractor.firstMatch(pattern: #"formhash=([A-Za-z0-9]+)"#, in: html)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func forumID(from url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "fid" })?
            .value?
            .nilIfBlank {
            return value
        }

        return HTMLTextExtractor.firstMatch(pattern: #"forum-(\d+)-\d+\.html"#, in: url.absoluteString)?
            .dropFirst()
            .first
    }

    private static func threadID(from url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tid" })?
            .value?
            .nilIfBlank {
            return value
        }

        return HTMLTextExtractor.firstMatch(pattern: #"thread-(\d+)-\d+-\d+\.html"#, in: url.absoluteString)?
            .dropFirst()
            .first
    }

    private static func todayCount(from text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"今日\s*(\d+)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func uniqueIdentifier(_ candidate: String, seen: inout Set<String>) -> String {
        guard !seen.insert(candidate).inserted else { return candidate }
        var suffix = 2
        while true {
            let next = "\(candidate)-\(suffix)"
            if seen.insert(next).inserted {
                return next
            }
            suffix += 1
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
