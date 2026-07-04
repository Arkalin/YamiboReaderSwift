import Foundation

public enum ForumHTMLParser {
    public static func parseHomePage(from html: String, fetchedAt: Date = .now) throws -> ForumHomePage {
        if YamiboHTMLPageInspector.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if YamiboHTMLPageInspector.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try KannaSoup.parse(html, baseURL: YamiboRoute.baseURL.absoluteString)
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
        if YamiboHTMLPageInspector.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if YamiboHTMLPageInspector.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try KannaSoup.parse(html, baseURL: YamiboRoute.baseURL.absoluteString)
        let documentTitle = (try? document.select("title").first()?.text())?
            .replacingOccurrences(of: " -  百合会.*", with: "", options: .regularExpression)
        let headerTitle = ((try? document.select(".header h2").first()?.text()) ?? "").nilIfBlank
        let top = try? document.select(".forumdisplay-top").first()
        let statsText = ((try? top?.select("p").text()) ?? "").normalizedForumText
        let resolvedTitle = title?.nilIfBlank ?? documentTitle
        let board = ForumBoardSummary(
            fid: fid,
            name: headerTitle ?? resolvedTitle?.nilIfBlank ?? L10n.string("forum.board"),
            todayCount: intAfter(label: "今日", in: statsText),
            threadCount: intAfter(label: "主题", in: statsText),
            rank: intAfter(label: "排名", in: statsText),
            iconURL: HTMLTextExtractor.absoluteURL(from: (try? top?.select("img[src]").first()?.attr("src")) ?? ""),
            url: ForumRouteResolver.boardURL(fid: fid)
        )
        return ForumBoardPage(
            board: board,
            subBoards: parseSubBoards(in: document),
            pinnedItems: parsePinnedItems(in: document),
            threads: parseThreadSummaries(in: document, fid: fid),
            pageNavigation: parsePageNavigation(in: document),
            filters: parseFilterOptions(in: document),
            orders: parseOrderOptions(in: document),
            formHash: parseFormHash(in: document, html: html),
            fetchedAt: fetchedAt
        )
    }

    public static func parseBoardFavoriteResult(from html: String) throws -> String {
        if YamiboHTMLPageInspector.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if YamiboHTMLPageInspector.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try KannaSoup.parse(html, baseURL: YamiboRoute.baseURL.absoluteString)
        let message = (
            (try? document.select(".jump_c, .alert_info, .messagetext, .showmessage, .wp").first()?.text())
                ?? (try? document.body()?.text())
                ?? ""
        ).normalizedForumText

        if message.contains("请先登录") || message.contains("請先登錄") || message.contains("请登录") {
            throw YamiboError.notAuthenticated
        }
        if message.contains("失败") || message.contains("失敗") || message.contains("错误") || message.contains("錯誤") {
            throw YamiboError.forumBoardFavoriteFailed
        }
        if message.contains("已收藏") || message.contains("收藏成功") || message.contains("成功收藏") {
            return message
        }

        guard !message.isEmpty else {
            throw YamiboError.forumBoardFavoriteFailed
        }
        return L10n.string("forum.board.favorite_success")
    }

    public static func parseSearchPage(from html: String, query: String) throws -> ForumSearchPage {
        if YamiboHTMLPageInspector.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if YamiboHTMLPageInspector.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try KannaSoup.parse(html, baseURL: YamiboRoute.baseURL.absoluteString)
        let results = parseThreadSummaries(in: document)
        guard !results.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.forum_search"))
        }

        return ForumSearchPage(
            query: query,
            searchID: parseSearchID(in: document, html: html),
            totalCount: parseSearchTotalCount(in: document),
            results: results,
            pageNavigation: parsePageNavigation(in: document)
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

    private static func parseSubBoards(in document: Document) -> [ForumBoardSummary] {
        let containers = (try? document.select(".forumlist .sub-forum")) ?? Elements()
        var boards: [ForumBoardSummary] = []
        var seen = Set<String>()

        for container in containers {
            for board in parseBoards(in: container) where seen.insert(board.fid).inserted {
                boards.append(board)
            }
        }

        return boards
    }

    private static func parsePinnedItems(in document: Document) -> [ForumPinnedItem] {
        let rows = (try? document.select(".threadlist li.list_top")) ?? Elements()
        var items: [ForumPinnedItem] = []
        var seen = Set<String>()

        for row in rows {
            guard let link = try? row.select("a[href]").first(),
                  let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? "") else {
                continue
            }

            let marker = ((try? link.select(".micon").first()?.text()) ?? "").normalizedForumText
            let title = (((try? link.select("em").first()?.text()) ?? (try? link.text()) ?? "")
                .replacingOccurrences(of: marker, with: ""))
                .normalizedForumText
            guard !title.isEmpty else { continue }

            let threadID = threadID(from: url)
            let kind: ForumPinnedItem.Kind = marker.contains("公告") || url.absoluteString.contains("mod=announcement")
                ? .announcement
                : .thread
            let id = threadID ?? url.absoluteString
            guard seen.insert(id).inserted else { continue }

            items.append(
                ForumPinnedItem(
                    id: id,
                    kind: kind,
                    title: title,
                    url: url,
                    threadID: threadID
                )
            )
        }

        return items
    }

    private static func parseThreadSummaries(in document: Document, fid: String? = nil) -> [ForumThreadSummary] {
        let rows = (try? document.select(".threadlist li.list")) ?? Elements()
        if !rows.isEmpty {
            return parseThreadRows(rows, fid: fid)
        }

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
            summaries.append(ForumThreadSummary(tid: tid, title: title, url: url, fid: fid))
        }

        return summaries
    }

    private static func parseThreadRows(_ rows: Elements, fid: String?) -> [ForumThreadSummary] {
        var summaries: [ForumThreadSummary] = []
        var seen = Set<String>()

        for row in rows {
            guard let titleLink = ((try? row.select(".threadlist_tit").first()?.parent()) ?? (try? row.select("a[href*='viewthread']").first())),
                  let url = HTMLTextExtractor.absoluteURL(from: (try? titleLink.attr("href")) ?? ""),
                  let tid = threadID(from: url),
                  seen.insert(tid).inserted else {
                continue
            }

            let titleContainer = try? row.select(".threadlist_tit").first()
            let marker = ((try? titleContainer?.select(".micon").text()) ?? "").normalizedForumText
            let title = (((try? titleContainer?.select("em").first()?.text()) ?? (try? titleLink.text()) ?? "")
                .replacingOccurrences(of: marker, with: ""))
                .normalizedForumText
            guard !title.isEmpty else { continue }

            let authorLink = try? row.select(".mmc[href]").first()
            let authorURL = HTMLTextExtractor.absoluteURL(from: (try? authorLink?.attr("href")) ?? "")
            let footerStats = parseThreadFooter(in: row)

            summaries.append(
                ForumThreadSummary(
                    tid: tid,
                    title: title,
                    url: url,
                    fid: fid,
                    authorName: ((try? authorLink?.text()) ?? "").nilIfBlank,
                    authorID: authorURL.flatMap(userID(from:)),
                    authorAvatarURL: HTMLTextExtractor.absoluteURL(from: (try? row.select(".mimg img[src]").first()?.attr("src")) ?? ""),
                    description: ((try? row.select(".threadlist_mes").first()?.text()) ?? "").nilIfBlank,
                    tag: footerStats.tag,
                    isPoll: marker.contains("投票"),
                    replyCount: footerStats.replyCount,
                    viewCount: footerStats.viewCount,
                    lastActivityText: ((try? row.select(".mtime").first()?.text()) ?? "").nilIfBlank
                )
            )
        }

        return summaries
    }

    private static func parseThreadFooter(in row: Element) -> (tag: String?, viewCount: Int?, replyCount: Int?) {
        let items = (try? row.select(".threadlist_foot li")) ?? Elements()
        var tag: String?
        var numbers: [Int] = []

        for item in items {
            let text = ((try? item.text()) ?? "").normalizedForumText
            if text.hasPrefix("#") {
                tag = String(text.dropFirst()).nilIfBlank
            } else if let number = firstInteger(in: text) {
                numbers.append(number)
            }
        }

        return (tag, numbers.first, numbers.dropFirst().first)
    }

    private static func parsePageNavigation(in document: Document) -> ForumPageNavigation? {
        guard let pager = try? document.select(".pg").first() else { return nil }
        let currentText = ((try? pager.select("strong").first()?.text()) ?? "").normalizedForumText
        let currentPage = Int(currentText) ?? 1
        let pagerText = ((try? pager.text()) ?? "").normalizedForumText
        let totalPages = HTMLTextExtractor.firstMatch(pattern: #"/\s*(\d+)\s*页"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
            ?? HTMLTextExtractor.firstMatch(pattern: #"\.\.\s*(\d+)"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)

        return ForumPageNavigation(currentPage: currentPage, totalPages: totalPages)
    }

    private static func parseSearchID(in document: Document, html: String) -> String? {
        let links = (try? document.select("a[href*='searchid=']")) ?? Elements()
        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let searchID = queryValue("searchid", in: url) else {
                continue
            }
            return searchID
        }

        return HTMLTextExtractor.firstMatch(pattern: #"searchid=(\d+)"#, in: html)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func parseSearchTotalCount(in document: Document) -> Int? {
        let text = ((try? document.select(".result, .searchlist, .threadlist_box").first()?.text()) ?? "").normalizedForumText
        guard text.contains("找到") || text.localizedCaseInsensitiveContains("result") else { return nil }
        return firstInteger(in: text)
    }

    private static func parseOrderOptions(in document: Document) -> [ForumOrderOption] {
        let links = (try? document.select(".dhnav_box a[href*='forumdisplay']")) ?? Elements()
        var options: [ForumOrderOption] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? "") else { continue }
            let title = ((try? link.text()) ?? "").normalizedForumText
            guard !title.isEmpty, title != "全部" else { continue }
            let filter = queryValue("filter", in: url)
            let orderBy = queryValue("orderby", in: url)
            let id = orderBy ?? filter ?? title
            guard seen.insert(id).inserted else { continue }
            options.append(ForumOrderOption(id: id, title: title, filter: filter, orderBy: orderBy))
        }

        return options
    }

    private static func parseFilterOptions(in document: Document) -> [ForumFilterOption] {
        let links = (try? document.select(".dhnavs_box a[href*='typeid=']")) ?? Elements()
        var options: [ForumFilterOption] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let id = queryValue("typeid", in: url) else {
                continue
            }
            let title = ((try? link.text()) ?? "").normalizedForumText
            guard !title.isEmpty, seen.insert(id).inserted else { continue }
            options.append(ForumFilterOption(id: id, title: title))
        }

        return options
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

    private static func userID(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "uid" })?
            .value?
            .nilIfBlank
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value?
            .nilIfBlank
    }

    private static func todayCount(from text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"今日\s*(\d+)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func intAfter(label: String, in text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"\#(label)\s*[:：]?\s*(\d+)"#, in: text)?
            .dropFirst()
            .last
            .flatMap(Int.init)
    }

    private static func firstInteger(in text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: text)?
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

    var normalizedForumText: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
