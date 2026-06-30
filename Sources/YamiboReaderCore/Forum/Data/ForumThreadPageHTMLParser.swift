import Foundation
import SwiftSoup

public enum ForumThreadPageHTMLParser {
    public static func parsePage(
        from html: String,
        thread: ThreadIdentity,
        fallbackTitle: String?
    ) throws -> ForumThreadPage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let title = ReaderHTMLParser.extractPageTitle(from: html)
            ?? fallbackTitle?.threadRoutingTrimmedNonEmpty
            ?? L10n.string("forum.default_title")
        let posts = try parsePosts(in: document)
        guard !posts.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("context.thread_page"))
        }
        let stats = parseThreadStats(in: document)

        return ForumThreadPage(
            thread: thread,
            title: title,
            posts: posts,
            pageNavigation: parsePageNavigation(in: document),
            totalViews: stats.totalViews,
            totalReplies: stats.totalReplies,
            forumID: parseForumID(in: document),
            forumName: parseForumName(in: document),
            formHash: parseFormHash(in: document, html: html)
        )
    }

    public static func parseRatingResults(from html: String) throws -> ForumThreadRatingResultsPage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let body = extractCData(from: html) ?? html
        let document = try SwiftSoup.parse(body, YamiboRoute.baseURL.absoluteString)
        let ratings = try ratingRows(in: document)
        guard !ratings.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("forum.thread.ratings_all"))
        }

        let pageText = try document.text()
        return ForumThreadRatingResultsPage(
            ratings: ratings,
            totalScore: explicitTotalScore(in: pageText) ?? ratings.compactMap(scoreValue).reduce(0, +)
        )
    }

    public static func parseRateOptions(from html: String) throws -> ForumThreadRateOptionsPage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let body = extractCData(from: html) ?? html
        let document = try SwiftSoup.parse(body, YamiboRoute.baseURL.absoluteString)
        let scores = try document.select("select#rate1 option").array()
            .compactMap { option in
                let value = try option.attr("value").threadRoutingTrimmedNonEmpty
                    ?? option.text().threadRoutingTrimmedNonEmpty
                return value.flatMap(Int.init)
            }
        let reasons = try document.select("select#reason option").array()
            .compactMap { option in
                try option.attr("value").threadRoutingTrimmedNonEmpty
                    ?? option.text().threadRoutingTrimmedNonEmpty
            }
        if scores.isEmpty && reasons.isEmpty,
           let message = parseMessageText(from: html) {
            throw YamiboError.underlying(message)
        }
        return ForumThreadRateOptionsPage(availableScores: scores, defaultReasons: reasons)
    }

    public static func parsePollVoters(
        from html: String,
        threadID: String,
        requestedOptionID: String? = nil
    ) throws -> ForumThreadPollVotersPage {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let requestedOptionID = requestedOptionID?.threadRoutingTrimmedNonEmpty
        let options = try pollVoterOptions(in: document, requestedOptionID: requestedOptionID)
        let selectedOptionID = pollSelectedOptionID(in: document) ?? requestedOptionID ?? options.first?.id
        let voters = try pollVoters(in: document)
        guard !options.isEmpty || !voters.isEmpty else {
            throw YamiboError.parsingFailed(context: L10n.string("forum.thread.poll_voters"))
        }

        return ForumThreadPollVotersPage(
            threadID: threadID,
            selectedOptionID: selectedOptionID,
            pollOptions: options,
            voters: voters,
            pageNavigation: parsePageNavigation(in: document)
        )
    }

    public static func parseThreadActionResult(
        from html: String,
        context: String = L10n.string("context.thread_page")
    ) throws -> String {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let body = extractCData(from: html) ?? html
        let document = try SwiftSoup.parse(body, YamiboRoute.baseURL.absoluteString)
        let message = firstNonBlank([
            parseMessageText(from: html),
            try? document.select(".jump_c, .alert_info, .messagetext, .showmessage, #messagetext, .wp, body").first()?.text()
        ])
        guard let message else {
            throw YamiboError.parsingFailed(context: context)
        }
        if (!html.contains("succeedhandle") && html.contains("<root"))
            || message.contains("失败")
            || message.contains("失敗")
            || message.contains("错误")
            || message.contains("錯誤")
            || message.localizedCaseInsensitiveContains("error") {
            throw YamiboError.underlying(message)
        }
        return message
    }

    private static func extractCData(from html: String) -> String? {
        guard let startRange = html.range(of: "<![CDATA[") else { return nil }
        let contentStart = startRange.upperBound
        guard let endRange = html.range(of: "]]>", range: contentStart ..< html.endIndex) else { return nil }
        return String(html[contentStart ..< endRange.lowerBound])
    }

    private static func parseMessageText(from html: String) -> String? {
        let body = extractCData(from: html) ?? html
        guard let document = try? SwiftSoup.parse(body, YamiboRoute.baseURL.absoluteString) else { return nil }
        return firstNonBlank([
            try? document.select("#messagetext p").first()?.text(),
            try? document.select("#messagetext, .messagetext, .alert_info, .jump_c, .showmessage").first()?.text()
        ])
    }

    private static func parsePosts(in document: Document) throws -> [ForumThreadPost] {
        let containers = try postContainers(in: document)
        var seen: Set<String> = []
        var posts: [ForumThreadPost] = []

        for container in containers {
            guard let body = try postBody(in: container),
                  let postID = postID(from: container, body: body),
                  seen.insert(postID).inserted else {
                continue
            }

            let lastEditedText = lastEditedText(in: container, body: body)
            let poll = try poll(in: container, body: body)
            let ratingBlock = try ratingBlock(in: container, postID: postID)
            let comments = try comments(in: container, postID: postID)
            let attachments = try footerAttachments(in: container, body: body)
            let manageActions = try manageActions(in: container)
            let contentBody = try bodyWithoutFooterMetadata(from: body)
            let contentHTML = try contentBody.html()
            let contentBlocks = try ForumThreadHTMLBlockParser.parseBlocks(in: contentBody)
            let contentText = normalizedBodyText(from: contentBlocks)
            guard !contentText.isEmpty
                || contentBlocks.contains(where: \.isNonTextRenderable)
                || poll != nil
                || ratingBlock != nil
                || !comments.isEmpty
                || !attachments.isEmpty
            else {
                continue
            }

            posts.append(
                ForumThreadPost(
                    postID: postID,
                    floorText: floorText(in: container),
                    author: author(in: container),
                    postedAtText: postedAtText(in: container),
                    lastEditedText: lastEditedText,
                    contentHTML: contentHTML,
                    contentText: contentText,
                    contentBlocks: contentBlocks,
                    poll: poll,
                    ratingBlock: ratingBlock,
                    comments: comments,
                    attachments: attachments,
                    isPinned: isPinned(container),
                    manageActions: manageActions
                )
            )
        }

        return posts
    }

    private static func postContainers(in document: Document) throws -> [Element] {
        let explicit = try document
            .select("[id^=post_], [id^=pid]")
            .array()
            .filter { element in
                ((try? postBody(in: element)) ?? nil) != nil
            }
        if !explicit.isEmpty {
            return explicit
        }

        return try document
            .select(".message, [id^=postmessage_]")
            .array()
    }

    private static func postBody(in container: Element) throws -> Element? {
        if isPostBody(container) {
            return container
        }
        return try container.select(".message, [id^=postmessage_], .t_f").first()
    }

    private static func isPostBody(_ element: Element) -> Bool {
        let rawID = element.id().trimmingCharacters(in: .whitespacesAndNewlines)
        return element.hasClass("message") || rawID.hasPrefix("postmessage_")
    }

    private static func postID(from container: Element, body: Element) -> String? {
        for element in [container, body] {
            let rawID = element.id().trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = postID(fromRawID: rawID, prefix: "post_") {
                return value
            }
            if let value = postID(fromRawID: rawID, prefix: "pid") {
                return value
            }
            if let value = postID(fromRawID: rawID, prefix: "postmessage_") {
                return value
            }
        }

        return nil
    }

    private static func postID(fromRawID rawID: String, prefix: String) -> String? {
        guard rawID.hasPrefix(prefix) else { return nil }
        return String(rawID.dropFirst(prefix.count)).threadRoutingTrimmedNonEmpty
    }

    private static func author(in container: Element) -> BlogReaderUser {
        let link = firstAuthorLink(in: container)
        let name = ((try? link?.text()) ?? "")
            .threadRoutingTrimmedNonEmpty
            ?? L10n.string("forum.thread.unknown_author")
        let uid = link.flatMap { userID(from: (try? $0.attr("href")) ?? "") }
        let avatarURL = HTMLTextExtractor.absoluteURL(from: (try? container.select("img[src]").first()?.attr("src")) ?? "")
        return BlogReaderUser(uid: uid, name: name, avatarURL: avatarURL)
    }

    private static func firstAuthorLink(in container: Element) -> Element? {
        let selectors = [
            ".authi a[href*='uid=']",
            ".authi a[href*='space-uid-']",
            "a.author",
            ".mtit a[href*='uid=']"
        ]
        for selector in selectors {
            if let link = try? container.select(selector).first() {
                return link
            }
        }
        return nil
    }

    private static func userID(from href: String) -> String? {
        guard let url = HTMLTextExtractor.absoluteURL(from: href) else { return nil }
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "uid" })?
            .value?
            .threadRoutingTrimmedNonEmpty {
            return value
        }
        return HTMLTextExtractor.firstMatch(pattern: #"space-uid-(\d+)"#, in: url.absoluteString)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func floorText(in container: Element) -> String? {
        let raw = [
            (try? container.select(".authi em[title]").first()?.attr("title")) ?? "",
            (try? container.select(".authi em").first()?.text()) ?? "",
            (try? container.select(".floor, .xg1").first()?.text()) ?? ""
        ]
            .joined(separator: " ")
        return HTMLTextExtractor.firstMatch(pattern: #"(\d+\s*#|楼主|樓主)"#, in: raw)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func postedAtText(in container: Element) -> String? {
        let text = ((try? container.select(".authi").first()?.text()) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return HTMLTextExtractor.firstMatch(pattern: #"(发表于|發表於)\s*([^|#]+)"#, in: text)?
            .dropFirst()
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func isPinned(_ container: Element) -> Bool {
        let text = normalizedInlineText((try? container.text()) ?? "")
        if text.contains("置顶") || text.contains("置頂") {
            return true
        }
        let classAndTitle = [
            (try? container.className()) ?? "",
            (try? container.select("[title]").array().map { try $0.attr("title") }.joined(separator: " ")) ?? "",
            (try? container.select("[class]").array().map { try $0.className() }.joined(separator: " ")) ?? ""
        ].joined(separator: " ").lowercased()
        return classAndTitle.contains("pin")
            || classAndTitle.contains("stick")
            || classAndTitle.contains("digest")
    }

    private static func manageActions(in container: Element) throws -> [ForumThreadManageAction] {
        let links = try container.select("a[href]").array()
        var seen: Set<String> = []
        var actions: [ForumThreadManageAction] = []
        for link in links {
            let rawTitle = try link.text().threadRoutingTrimmedNonEmpty
                ?? link.attr("title").threadRoutingTrimmedNonEmpty
            guard let rawTitle,
                  try isManageActionLink(link, title: rawTitle),
                  let url = HTMLTextExtractor.absoluteURL(from: try link.attr("href")) else {
                continue
            }
            let action = ForumThreadManageAction(title: rawTitle, url: url)
            if seen.insert(action.id).inserted {
                actions.append(action)
            }
        }
        return actions
    }

    private static func isManageActionLink(_ link: Element, title: String) throws -> Bool {
        guard isManageActionTitle(title) else { return false }
        let href = try link.attr("href").lowercased()
        if href.contains("modcp")
            || href.contains("topicadmin")
            || href.contains("action=moderate")
            || href.contains("action=edit")
            || href.contains("action=delpost")
            || href.contains("action=warn") {
            return true
        }

        let parentClassTokens = Set(
            link.parents()
                .flatMap { ((try? $0.className().lowercased()) ?? "").split(whereSeparator: \.isWhitespace).map(String.init) }
        )
        return !parentClassTokens.isDisjoint(with: ["po", "pob", "manage", "postmanage"])
    }

    private static func isManageActionTitle(_ title: String) -> Bool {
        let normalized = normalizedInlineText(title)
        let allowed = [
            "管理",
            "编辑",
            "編輯",
            "删除",
            "刪除",
            "评分",
            "評分",
            "警告",
            "屏蔽",
            "置顶",
            "置頂",
            "精华",
            "精華",
            "提升",
            "下沉"
        ]
        return allowed.contains { normalized.contains($0) }
    }

    private static func lastEditedText(in container: Element, body: Element) -> String? {
        let selectors = [
            ".pstatus",
            ".lastedit",
            ".editinfo",
            ".edited"
        ]
        for selector in selectors {
            for element in ((try? body.select(selector).array()) ?? []) + ((try? container.select(selector).array()) ?? []) {
                let text = ((try? element.text()) ?? "")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .threadRoutingTrimmedNonEmpty
                if let text {
                    return text
                }
            }
        }

        let bodyText = ((try? body.text()) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return HTMLTextExtractor.firstMatch(
            pattern: #"(本帖最后由\s+.+?\s+于\s+.+?\s+编辑|本帖最後由\s+.+?\s+於\s+.+?\s+編輯|最后编辑于\s*.+|最後編輯於\s*.+)"#,
            in: bodyText
        )?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func bodyWithoutFooterMetadata(from body: Element) throws -> Element {
        let document = try SwiftSoup.parseBodyFragment(try body.html(), YamiboRoute.baseURL.absoluteString)
        let copy = document.body() ?? document
        try copy.select(
            [
                ".pstatus",
                ".lastedit",
                ".editinfo",
                ".edited",
                "[id^=ratelog_]",
                ".ratelog",
                ".ratl",
                ".cm",
                "[id^=comment_]",
                ".pcht",
                ".poll",
                "#poll",
                ".polls"
            ].joined(separator: ", ")
        ).remove()
        return copy
    }

    private static func normalizedBodyText(from blocks: [ForumThreadContentBlock]) -> String {
        let text = blocks.flatMap(\.plainTextFragments).joined(separator: "\n")
        return ForumThreadHTMLBlockParser.normalizeCommittedText(text)
    }

    private static func poll(in container: Element, body: Element) throws -> ForumThreadPoll? {
        let candidates = try uniqueElements(
            [
                body.select("#poll, .poll, .polls, .pcht").array(),
                container.select("#poll, .poll, .polls, .pcht").array()
            ].flatMap { $0 }
        )
        guard let pollElement = candidates.first(where: { element in
            (((try? element.select("input[type=radio], input[type=checkbox]").isEmpty()) ?? true) == false)
                || (((try? element.text().contains("%")) ?? false) == true)
        }) else {
            return nil
        }

        let inputElements = try pollElement.select("input[type=radio], input[type=checkbox]").array()
        let isMultipleChoice = inputElements.contains { (((try? $0.attr("type")) ?? "").lowercased() == "checkbox") }
        let status: ForumThreadPollStatus = inputElements.isEmpty
            ? .voted
            : .notVoted
        let type: ForumThreadPollType = inputElements.isEmpty
            ? .unknown
            : (isMultipleChoice ? .multipleChoice : .singleChoice)
        let options = try pollOptions(in: pollElement, inputs: inputElements)
        guard !options.isEmpty else { return nil }

        return ForumThreadPoll(
            title: pollTitle(in: pollElement) ?? L10n.string("forum.thread.poll"),
            endTimeText: pollEndTime(in: pollElement),
            type: type,
            status: status,
            options: options
        )
    }

    private static func pollOptions(
        in pollElement: Element,
        inputs: [Element]
    ) throws -> [ForumThreadPollOption] {
        if !inputs.isEmpty {
            return try inputs.enumerated().compactMap { index, input in
                let row = nearestAncestor(
                    of: input,
                    matching: { element in
                        let tag = element.tagName().lowercased()
                        return tag == "tr" || tag == "li" || tag == "p" || element.hasClass("polloption")
                    }
                ) ?? input.parent()
                let rawText = try (row ?? input).text()
                let inputValue = try input.attr("value")
                let optionText = optionTitle(from: rawText)
                    ?? inputValue.threadRoutingTrimmedNonEmpty
                    ?? "\(index + 1)"
                return ForumThreadPollOption(
                    id: inputValue.threadRoutingTrimmedNonEmpty ?? "\(index)",
                    title: optionText,
                    voteCount: voteCount(in: rawText),
                    percentage: percentage(in: rawText),
                    isSelected: try !input.attr("checked").isEmpty
                )
            }
        }

        let rows = try pollElement.select("tr, li, p").array()
        return rows.enumerated().compactMap { index, row in
            let text = normalizedInlineText((try? row.text()) ?? "")
            guard text.contains("%"),
                  let title = optionTitle(from: text) else {
                return nil
            }
            return ForumThreadPollOption(
                id: "\(index)",
                title: title,
                voteCount: voteCount(in: text),
                percentage: percentage(in: text)
            )
        }
    }

    private static func pollTitle(in pollElement: Element) -> String? {
        let selectors = ["h3", "h4", ".polltitle", ".xs2", ".pcht h4", "caption"]
        for selector in selectors {
            if let text = ((try? pollElement.select(selector).first()?.text()) ?? "")
                .threadRoutingTrimmedNonEmpty {
                return text
            }
        }
        let text = normalizedInlineText((try? pollElement.text()) ?? "")
        return text
            .components(separatedBy: CharacterSet(charactersIn: "。.!?？\n"))
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func pollEndTime(in pollElement: Element) -> String? {
        for selector in ["p", ".xg1", ".polltime", ".poll_time"] {
            for element in ((try? pollElement.select(selector).array()) ?? []) {
                let text = normalizedInlineText((try? element.text()) ?? "")
                guard text.contains("结束")
                    || text.contains("結束")
                    || text.contains("截止")
                    || text.contains("投票截止") else {
                    continue
                }
                if let value = HTMLTextExtractor.firstMatch(
                    pattern: #"(?:结束时间|結束時間|截止时间|截止時間|投票截止)[:：]?\s*(.+)$"#,
                    in: text
                )?
                    .dropFirst()
                    .first?
                    .threadRoutingTrimmedNonEmpty {
                    return value
                }
            }
        }

        let text = normalizedInlineText((try? pollElement.text()) ?? "")
        return HTMLTextExtractor.firstMatch(
            pattern: #"(结束时间|結束時間|截止时间|截止時間|投票截止)[:：]?\s*([0-9]{4}[-/年][^。；;\n ]+(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)"#,
            in: text
        )?
            .dropFirst()
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }

    private static func optionTitle(from text: String) -> String? {
        var value = text
            .replacingOccurrences(of: #"\d+(?:\.\d+)?%\s*(?:\(\d+\))?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d+\s*(?:票|人|votes?)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*[\[\]☑✓○●•\-\d.、]+\s*"#, with: "", options: .regularExpression)
        value = normalizedInlineText(value)
        return value.threadRoutingTrimmedNonEmpty
    }

    private static func ratingBlock(in container: Element, postID: String) throws -> ForumThreadRatingBlock? {
        let candidates = try uniqueElements(
            [
                container.select("#ratelog_\(postID)").array(),
                container.select("[id^=ratelog_], .ratelog, .ratl").array()
            ].flatMap { $0 }
        )
        guard let element = candidates.first else { return nil }

        let allRatingsURL = try element.select("a[href*='action=viewratings']").first()
            .flatMap { HTMLTextExtractor.absoluteURL(from: try $0.attr("href")) }
        let ratings = try ratingRows(in: element)
        guard !ratings.isEmpty || allRatingsURL != nil else { return nil }
        let totalScore = explicitTotalScore(in: try element.text()) ?? ratings.compactMap(scoreValue).reduce(0, +)
        let participantCount = participantCount(in: try element.text()) ?? ratings.count
        return ForumThreadRatingBlock(
            participantCount: participantCount,
            totalScore: totalScore,
            ratings: ratings,
            allRatingsURL: allRatingsURL
        )
    }

    private static func ratingRows(in element: Element) throws -> [ForumThreadRating] {
        try element.select("li, tr").array().compactMap(ratingRow)
    }

    private static func ratingRow(_ row: Element) throws -> ForumThreadRating? {
        let text = normalizedInlineText(try row.text())
        guard !text.isEmpty,
              !text.contains("参与人数"),
              !text.contains("參與人數"),
              !text.contains("查看全部"),
              !text.localizedCaseInsensitiveContains("viewratings") else {
            return nil
        }

        let cells = try row.select("td, th, div").array()
        guard cells.count >= 2 else { return nil }
        let first = cells[0]
        let userLink = try first.select("a[href*='uid='], a[href*='space-uid-'], a").first()
        let userName = normalizedInlineText(try (userLink ?? first).text())
            .threadRoutingTrimmedNonEmpty
            ?? L10n.string("forum.thread.unknown_author")
        let scoreText = normalizedInlineText(try cells[1].text())
        guard scoreText.contains("+") || scoreText.contains("-") || Int(scoreText) != nil else {
            return nil
        }
        let reason = cells.dropFirst(2)
            .map { normalizedInlineText((try? $0.text()) ?? "") }
            .joined(separator: " ")
            .threadRoutingTrimmedNonEmpty
        let uid = userLink.flatMap { userID(from: (try? $0.attr("href")) ?? "") }
        return ForumThreadRating(
            user: BlogReaderUser(uid: uid, name: userName, avatarURL: nil),
            scoreText: scoreText,
            reason: reason
        )
    }

    private static func pollVoterOptions(
        in document: Document,
        requestedOptionID: String?
    ) throws -> [ForumThreadPollVoterOption] {
        var options: [ForumThreadPollVoterOption] = []
        var seen: Set<String> = []

        for option in try document.select("select option[value], option[value]").array() {
            let id = try option.attr("value").threadRoutingTrimmedNonEmpty
            let name = try option.text().threadRoutingTrimmedNonEmpty
            guard let id, let name, seen.insert(id).inserted else { continue }
            options.append(ForumThreadPollVoterOption(id: id, name: name))
        }

        for link in try document.select("a[href*='polloptionid=']").array() {
            let href = try link.attr("href")
            guard let url = HTMLTextExtractor.absoluteURL(from: href),
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "polloptionid" })?
                    .value?
                    .threadRoutingTrimmedNonEmpty,
                  seen.insert(id).inserted else {
                continue
            }
            let name = try link.text().threadRoutingTrimmedNonEmpty ?? id
            options.append(ForumThreadPollVoterOption(id: id, name: name))
        }

        if let requestedOptionID, !seen.contains(requestedOptionID) {
            options.insert(ForumThreadPollVoterOption(id: requestedOptionID, name: requestedOptionID), at: 0)
        }

        return options
    }

    private static func pollSelectedOptionID(in document: Document) -> String? {
        if let value = ((try? document.select("select option[selected]").first()?.attr("value")) ?? "")
            .threadRoutingTrimmedNonEmpty {
            return value
        }
        for selector in ["a.a[href*='polloptionid=']", "a.xw1[href*='polloptionid=']", "strong a[href*='polloptionid=']"] {
            if let href = (try? document.select(selector).first()?.attr("href")),
               let url = HTMLTextExtractor.absoluteURL(from: href),
               let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "polloptionid" })?
                .value?
                .threadRoutingTrimmedNonEmpty {
                return value
            }
        }
        return nil
    }

    private static func pollVoters(in document: Document) throws -> [BlogReaderUser] {
        var voters: [BlogReaderUser] = []
        var seen: Set<String> = []

        for link in try document.select("a[href*='uid='], a[href*='space-uid-']").array() {
            let name = try link.text().threadRoutingTrimmedNonEmpty
            let uid = userID(from: try link.attr("href"))
            guard let name, uid != nil || !name.isEmpty else { continue }
            let key = uid ?? name
            guard seen.insert(key).inserted else { continue }
            voters.append(BlogReaderUser(uid: uid, name: name, avatarURL: nil))
        }

        return voters
    }

    private static func comments(in container: Element, postID: String) throws -> [ForumThreadPostComment] {
        let roots = try uniqueElements(
            [
                container.select("#comment_\(postID)").array(),
                container.select(".cm, [id^=comment_]").array()
            ].flatMap { $0 }
        )
        var comments: [ForumThreadPostComment] = []
        var seen: Set<String> = []

        for root in roots {
            let rows = try root.select(".pstl, li, .comment").array()
            let commentRows = rows.isEmpty ? [root] : rows
            for (index, row) in commentRows.enumerated() {
                guard let comment = try comment(in: row, root: root, postID: postID, index: index),
                      seen.insert(comment.id).inserted else {
                    continue
                }
                comments.append(comment)
            }
        }
        return comments
    }

    private static func comment(
        in row: Element,
        root: Element,
        postID: String,
        index: Int
    ) throws -> ForumThreadPostComment? {
        let messageElement = try row.select(".psti, .comment_content, .message").first() ?? row
        let metadataText = try messageElement.select(".xg1, .time, .date").array()
            .compactMap { try $0.text().threadRoutingTrimmedNonEmpty }
            .joined(separator: " ")
            .threadRoutingTrimmedNonEmpty
        let messageDocument = try SwiftSoup.parseBodyFragment(try messageElement.html(), YamiboRoute.baseURL.absoluteString)
        let messageBody = messageDocument.body() ?? messageDocument
        try messageBody.select(".xg1, .time, .date").remove()
        let message = normalizedInlineText(try messageBody.text())
        guard !message.isEmpty else { return nil }

        let authorLink = try row.select(".psta a[href*='uid='], .psta a[href*='space-uid-'], .psta a, a[href*='uid='], a[href*='space-uid-']").first()
        let authorName = normalizedInlineText(try authorLink?.text() ?? "")
            .threadRoutingTrimmedNonEmpty
            ?? L10n.string("reader.comment_anonymous")
        let uid = authorLink.flatMap { userID(from: (try? $0.attr("href")) ?? "") }
        let id = root.id().threadRoutingTrimmedNonEmpty.map { "\($0)-\(index)" }
            ?? "\(postID)-comment-\(index)"
        return ForumThreadPostComment(
            id: id,
            author: BlogReaderUser(uid: uid, name: authorName, avatarURL: nil),
            postedAtText: metadataText,
            message: message
        )
    }

    private static func footerAttachments(in container: Element, body: Element) throws -> [ForumThreadAttachmentBlock] {
        let bodyElementID = body.id()
        let candidates = try container.select(".pattl, .attach, .t_attach, [id^=attach_]").array()
            .filter { element in
                guard !bodyElementID.isEmpty else { return true }
                return element.parents().contains { $0.id() == bodyElementID } != true
            }
        return try candidates.compactMap(attachmentFromFooterElement)
    }

    private static func attachmentFromFooterElement(_ element: Element) throws -> ForumThreadAttachmentBlock? {
        guard let link = try element.select("a[href]").first(),
              let url = HTMLTextExtractor.absoluteURL(from: try link.attr("href")) else {
            return nil
        }
        let text = normalizedInlineText(try element.text())
        let fileName = try link.text().threadRoutingTrimmedNonEmpty
            ?? text.components(separatedBy: " ").first?.threadRoutingTrimmedNonEmpty
        guard let fileName else { return nil }
        let statInfo = HTMLTextExtractor.firstMatch(
            pattern: #"((?:\d+(?:\.\d+)?\s*(?:KB|MB|GB|字节|位元組|bytes?))|(?:\d+\s*(?:次下载|次下載|downloads?)))"#,
            in: text
        )?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
        return ForumThreadAttachmentBlock(
            url: url,
            iconURL: try element.select("img[src]").first().flatMap { HTMLTextExtractor.absoluteURL(from: try $0.attr("src")) },
            fileName: fileName,
            uploadInfo: nil,
            statInfo: statInfo
        )
    }

    private static func uniqueElements(_ elements: [Element]) throws -> [Element] {
        var result: [Element] = []
        var seen: Set<String> = []
        for (index, element) in elements.enumerated() {
            let key = try element.cssSelector().threadRoutingTrimmedNonEmpty ?? "\(element.tagName())-\(element.id())-\(index)"
            if seen.insert(key).inserted {
                result.append(element)
            }
        }
        return result
    }

    private static func nearestAncestor(
        of element: Element,
        matching predicate: (Element) -> Bool
    ) -> Element? {
        var current = element.parent()
        while let candidate = current {
            if predicate(candidate) {
                return candidate
            }
            current = candidate.parent()
        }
        return nil
    }

    private static func normalizedInlineText(_ value: String) -> String {
        HTMLTextExtractor.decodeHTMLEntities(value)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonBlank(_ values: [String?]) -> String? {
        values.lazy.compactMap { $0?.threadRoutingTrimmedNonEmpty }.first
    }

    private static func percentage(in text: String) -> Double? {
        HTMLTextExtractor.firstMatch(pattern: #"(\d+(?:\.\d+)?)\s*%"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Double.init)
    }

    private static func voteCount(in text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"(\d+)\s*(?:票|人|votes?)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func participantCount(in text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"(?:参与人数|參與人數|共)\D*(\d+)\D*(?:人)?"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func explicitTotalScore(in text: String) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"(?:总积分|總積分|积分|積分)\D*([+-]?\d+)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func scoreValue(_ rating: ForumThreadRating) -> Int? {
        HTMLTextExtractor.firstMatch(pattern: #"([+-]?\d+)"#, in: rating.scoreText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func parsePageNavigation(in document: Document) -> ForumPageNavigation? {
        guard let pager = try? document.select(".pg").first() else { return nil }
        let currentText = (((try? pager.select("strong").first()?.text()) ?? "") as String)
            .threadRoutingTrimmedNonEmpty
        let currentPage = currentText.flatMap(Int.init) ?? 1
        let pagerText = ((try? pager.text()) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

    private static func parseThreadStats(in document: Document) -> (totalViews: Int?, totalReplies: Int?) {
        let candidateText = [
            ".thread-meta",
            ".thread_stats",
            ".threadstats",
            ".thread_info",
            ".thread-info",
            ".threadlist_foot",
            ".vwthd",
            ".ts",
            ".hm",
            "#thread_subject"
        ]
            .compactMap { selector in
                ((try? document.select(selector).text()) ?? "").threadRoutingTrimmedNonEmpty
            }
            .joined(separator: " ")

        let fallbackText = candidateText.threadRoutingTrimmedNonEmpty
            ?? ((try? document.body()?.text()) ?? "")
        return (
            totalViews: intAfterAny(labels: ["查看", "浏览", "瀏覽", "阅读", "閱讀", "views", "view"], in: fallbackText),
            totalReplies: intAfterAny(labels: ["回复", "回復", "回覆", "评论", "評論", "replies", "reply", "comments", "comment"], in: fallbackText)
        )
    }

    private static func intAfterAny(labels: [String], in text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for label in labels {
            if let value = HTMLTextExtractor.firstMatch(
                pattern: #"\#(label)\s*[:：]?\s*(\d+)"#,
                in: normalized
            )?
                .dropFirst()
                .last
                .flatMap(Int.init) {
                return value
            }
        }
        return nil
    }

    private static func parseForumName(in document: Document) -> String? {
        let selectors = [
            "#pt a[href*='forum.php?mod=forumdisplay']",
            "#pt a[href*='fid=']",
            ".bm_h a[href*='forum.php?mod=forumdisplay']",
            ".bm_h a[href*='fid=']",
            "a[href*='forum.php?mod=forumdisplay']"
        ]
        for selector in selectors {
            let values = ((try? document.select(selector).array()) ?? [])
                .compactMap { element in
                    ((try? element.text()) ?? "").threadRoutingTrimmedNonEmpty
                }
                .filter { value in
                    value != L10n.string("forum.default_title")
                }
            if let value = values.last {
                return value
            }
        }
        return nil
    }

    private static func parseForumID(in document: Document) -> String? {
        let selectors = [
            "#pt a[href*='fid=']",
            ".bm_h a[href*='fid=']",
            "a[href*='forum.php?mod=forumdisplay']",
            "a[href*='fid=']"
        ]
        for selector in selectors {
            for link in ((try? document.select(selector).array()) ?? []) {
                guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                      let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "fid" })?
                    .value?
                    .threadRoutingTrimmedNonEmpty else {
                    continue
                }
                return value
            }
        }
        return nil
    }

    private static func parseFormHash(in document: Document, html: String) -> String? {
        if let value = try? document.select("input[name=formhash]").first()?.attr("value"),
           let formHash = value.threadRoutingTrimmedNonEmpty {
            return formHash
        }
        return HTMLTextExtractor.firstMatch(pattern: #"formhash=([A-Za-z0-9]+)"#, in: html)?
            .dropFirst()
            .first?
            .threadRoutingTrimmedNonEmpty
    }
}

private extension ForumThreadContentBlock {
    var isNonTextRenderable: Bool {
        switch kind {
        case .image, .attachment, .horizontalRule, .table:
            true
        case let .quote(blocks), let .collapse(_, blocks), let .locked(_, blocks):
            blocks.contains(where: \.isNonTextRenderable) || !plainTextFragments.isEmpty
        case .text, .code:
            false
        }
    }

    var plainTextFragments: [String] {
        switch kind {
        case let .text(block):
            [block.text]
        case let .attachment(block):
            [block.fileName]
        case let .quote(blocks), let .collapse(_, blocks), let .locked(_, blocks):
            blocks.flatMap(\.plainTextFragments)
        case let .code(text):
            [text]
        case let .table(rows):
            rows.flatMap { row in row.flatMap { cell in cell.blocks.flatMap(\.plainTextFragments) } }
        case .image, .horizontalRule:
            []
        }
    }
}

enum ForumThreadHTMLBlockParser {
    static func parseBlocks(in body: Element) throws -> [ForumThreadContentBlock] {
        let copy = try SwiftSoup.parseBodyFragment(try body.html(), YamiboRoute.baseURL.absoluteString)
        try sanitize(copy.body() ?? copy)
        return normalizeBlocks(try BlockBuilder().parse(nodes: (copy.body() ?? copy).getChildNodes()))
    }

    static func parseBlocks(fromHTML html: String) throws -> [ForumThreadContentBlock] {
        let document = try SwiftSoup.parseBodyFragment(html, YamiboRoute.baseURL.absoluteString)
        try sanitize(document.body() ?? document)
        return normalizeBlocks(try BlockBuilder().parse(nodes: (document.body() ?? document).getChildNodes()))
    }

    static func normalizeCommittedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitize(_ element: Element) throws {
        try element.select("font.jammer, .jammer").remove()
        for styledElement in try element.select("[style]").array() {
            let style = try styledElement.attr("style").lowercased().replacingOccurrences(of: " ", with: "")
            if style.contains("display:none") {
                try styledElement.remove()
            }
        }
    }

    private static func normalizeBlocks(_ blocks: [ForumThreadContentBlock]) -> [ForumThreadContentBlock] {
        blocks.flatMap(normalizedBlock)
    }

    private static func normalizedBlock(_ block: ForumThreadContentBlock) -> [ForumThreadContentBlock] {
        switch block.kind {
        case let .text(textBlock):
            splitTextBlock(blockID: block.id, block: textBlock)
        case let .quote(blocks):
            [ForumThreadContentBlock(id: block.id, kind: .quote(normalizeBlocks(blocks)))]
        case let .collapse(title, blocks):
            [ForumThreadContentBlock(id: block.id, kind: .collapse(title: title, contentBlocks: normalizeBlocks(blocks)))]
        case let .locked(cost, blocks):
            [ForumThreadContentBlock(id: block.id, kind: .locked(cost: cost, contentBlocks: normalizeBlocks(blocks)))]
        case let .table(rows):
            [
                ForumThreadContentBlock(
                    id: block.id,
                    kind: .table(
                        rows: rows.map { row in
                            row.map { cell in
                                ForumThreadTableCell(
                                    isHeader: cell.isHeader,
                                    blocks: normalizeBlocks(cell.blocks)
                                )
                            }
                        }
                    )
                )
            ]
        default:
            [block]
        }
    }

    private static func splitTextBlock(
        blockID: String,
        block: ForumThreadTextBlock,
        maxCharacters: Int = 320
    ) -> [ForumThreadContentBlock] {
        let characters = Array(block.text)
        guard characters.count > maxCharacters else {
            return [ForumThreadContentBlock(id: blockID, kind: .text(block))]
        }

        var chunks: [ForumThreadContentBlock] = []
        var start = 0
        while start < characters.count {
            let preferredEnd = min(start + maxCharacters, characters.count)
            let end: Int
            if preferredEnd < characters.count,
               let newlineIndex = characters[start ..< preferredEnd].lastIndex(of: "\n"),
               newlineIndex > start + maxCharacters / 3 {
                end = newlineIndex + 1
            } else {
                end = preferredEnd
            }

            let chunkText = String(characters[start ..< end])
            let chunkLinks = block.links.compactMap { link -> ForumThreadTextLink? in
                let linkStart = link.start
                let linkEnd = link.start + link.length
                let overlapStart = max(start, linkStart)
                let overlapEnd = min(end, linkEnd)
                guard overlapEnd > overlapStart else { return nil }
                return ForumThreadTextLink(
                    start: overlapStart - start,
                    length: overlapEnd - overlapStart,
                    url: link.url
                )
            }
            let chunkStyleRuns = block.styleRuns.compactMap { run -> ForumThreadTextStyleRun? in
                let runStart = run.start
                let runEnd = run.start + run.length
                let overlapStart = max(start, runStart)
                let overlapEnd = min(end, runEnd)
                guard overlapEnd > overlapStart else { return nil }
                return ForumThreadTextStyleRun(
                    start: overlapStart - start,
                    length: overlapEnd - overlapStart,
                    style: run.style
                )
            }
            let chunkRubies = block.rubies.compactMap { ruby -> ForumThreadRubyText? in
                let rubyStart = ruby.start
                let rubyEnd = ruby.start + ruby.length
                guard rubyStart >= start, rubyEnd <= end else { return nil }
                return ForumThreadRubyText(
                    start: rubyStart - start,
                    length: ruby.length,
                    baseText: ruby.baseText,
                    rubyText: ruby.rubyText
                )
            }
            chunks.append(
                ForumThreadContentBlock(
                    id: start == 0 ? blockID : "\(blockID)-\(start)",
                    kind: .text(
                        ForumThreadTextBlock(
                            text: chunkText,
                            alignment: block.alignment,
                            links: chunkLinks,
                            styleRuns: chunkStyleRuns,
                            rubies: chunkRubies
                        )
                    )
                )
            )
            start = end
        }
        return chunks
    }

    private struct PendingTextLink {
        var start: Int
        var length: Int
        var url: URL
    }

    private struct PendingTextStyleRun {
        var start: Int
        var length: Int
        var style: ForumThreadTextStyle
    }

    private struct PendingRubyText {
        var start: Int
        var length: Int
        var baseText: String
        var rubyText: String
    }

    private final class BlockBuilder {
        private var blocks: [ForumThreadContentBlock] = []
        private var text = ""
        private var links: [PendingTextLink] = []
        private var styleRuns: [PendingTextStyleRun] = []
        private var rubies: [PendingRubyText] = []
        private var currentLinkURL: URL?
        private var currentStyle = ForumThreadTextStyle()
        private var currentAlignment = ForumThreadTextAlignment.start
        private var blockCounter = 0

        func parse(nodes: [Node]) throws -> [ForumThreadContentBlock] {
            for node in nodes {
                try parse(node: node)
            }
            commitText()
            return blocks
        }

        private func parse(node: Node) throws {
            if let textNode = node as? TextNode {
                appendTextNodeText(textNode.getWholeText())
                return
            }

            guard let element = node as? Element else {
                for child in node.getChildNodes() {
                    try parse(node: child)
                }
                return
            }

            let tagName = element.tagName().lowercased()
            switch tagName {
            case "br":
                appendLineBreak(explicit: true)
            case "hr":
                commitText()
                appendBlock(.horizontalRule, seed: "hr")
            case "img":
                try appendImage(from: element)
            case "blockquote":
                try appendQuote(from: element)
            case "div":
                try parseDiv(element)
            case "pre":
                commitText()
                appendBlock(.code(try element.text()), seed: "code-\(try element.text())")
            case "table":
                try parseTable(element)
            case "ul":
                try parseUnorderedList(element)
            case "a":
                try parseLink(element)
            case "b", "strong":
                try withTextStyle(ForumThreadTextStyle(isBold: true)) {
                    try parseChildren(of: element)
                }
            case "i", "em":
                try withTextStyle(ForumThreadTextStyle(isItalic: true)) {
                    try parseChildren(of: element)
                }
            case "u":
                try withTextStyle(ForumThreadTextStyle(isUnderline: true)) {
                    try parseChildren(of: element)
                }
            case "s", "strike":
                try withTextStyle(ForumThreadTextStyle(isStrikethrough: true)) {
                    try parseChildren(of: element)
                }
            case "ruby":
                try parseRuby(element)
            case "rt":
                return
            case "font":
                try withTextStyle(textStyle(fromFontElement: element)) {
                    try parseChildren(of: element)
                }
            case "span":
                try withTextStyle(textStyle(fromStyleAttribute: try element.attr("style"))) {
                    try parseChildren(of: element)
                }
            case "p":
                try parseBlockContainer(element)
            case "ol", "tbody", "tr", "td", "th":
                appendLineBreak(maxConsecutive: 1)
                try parseChildren(of: element)
                appendLineBreak(maxConsecutive: 1)
            case "li":
                appendLineBreak(maxConsecutive: 1)
                appendText("• ")
                try parseChildren(of: element)
                appendLineBreak(maxConsecutive: 1)
            case "script", "style":
                return
            default:
                try parseChildren(of: element)
            }
        }

        private func parseDiv(_ element: Element) throws {
            let classes = try element.className().lowercased()
            if classes.contains("showcollapse_box") {
                commitText()
                let titleNode = try element.select(".showcollapse_title").first()
                let title = try titleNode?.text().threadRoutingTrimmedNonEmpty
                try titleNode?.remove()
                let contentBlocks = try ForumThreadHTMLBlockParser.parseBlocks(fromHTML: try element.html())
                appendBlock(
                    .collapse(title: title, contentBlocks: contentBlocks),
                    seed: "collapse-\(title ?? "")"
                )
                return
            }

            if classes.contains("locked-content") {
                commitText()
                let costText = try element.select(".locked-tip").text()
                let cost = HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: costText)?
                    .dropFirst()
                    .first
                    .flatMap(Int.init)
                try element.select(".locked-tip").remove()
                let contentBlocks = try ForumThreadHTMLBlockParser.parseBlocks(fromHTML: try element.html())
                appendBlock(
                    .locked(cost: cost, contentBlocks: contentBlocks),
                    seed: "locked-\(costText)"
                )
                return
            }

            if classes.contains("quote") || classes.contains("blockquote") {
                try appendQuote(from: element)
                return
            }

            if classes.contains("blockcode") {
                commitText()
                appendBlock(.code(try element.text()), seed: "code-\(try element.text())")
                return
            }

            try parseBlockContainer(element)
        }

        private func parseBlockContainer(_ element: Element) throws {
            let alignment = try textAlignment(from: element) ?? currentAlignment
            try withTextAlignment(alignment) {
                appendLineBreak(maxConsecutive: 1)
                try parseChildren(of: element)
                appendLineBreak(maxConsecutive: 1)
            }
        }

        private func parseTable(_ element: Element) throws {
            let rows = try element.select("tr").array()
            let isDataTable = try rows.contains { row in
                try row.select("td, th").array().count > 1
            }
            guard isDataTable else {
                appendLineBreak(maxConsecutive: 1)
                try parseChildren(of: element)
                appendLineBreak(maxConsecutive: 1)
                return
            }

            commitText()
            let tableRows = try rows.map { row in
                try row.select("td, th").array().map { cell in
                    let tagName = cell.tagName().lowercased()
                    let hasStrongText = !(try cell.select("strong, b").array().isEmpty)
                    let isHeader = tagName == "th" || hasStrongText
                    return ForumThreadTableCell(
                        isHeader: isHeader,
                        blocks: try ForumThreadHTMLBlockParser.parseBlocks(fromHTML: try cell.html())
                    )
                }
            }
            appendBlock(.table(rows: tableRows), seed: "table-\(tableRows.count)")
        }

        private func parseUnorderedList(_ element: Element) throws {
            let classes = try element.className().lowercased()
            if classes.contains("post_attlist"), let attachment = try attachment(from: element) {
                commitText()
                appendBlock(.attachment(attachment), seed: "attachment-\(attachment.fileName)")
                return
            }

            appendLineBreak(maxConsecutive: 1)
            try parseChildren(of: element)
            appendLineBreak(maxConsecutive: 1)
        }

        private func parseLink(_ element: Element) throws {
            guard let url = HTMLTextExtractor.absoluteURL(from: try element.attr("href")) else {
                try parseChildren(of: element)
                return
            }

            let previousLinkURL = currentLinkURL
            currentLinkURL = url
            let start = text.count
            try parseChildren(of: element)
            let end = text.count
            if end > start {
                links.append(PendingTextLink(start: start, length: end - start, url: url))
            } else {
                appendText(try element.text())
                let linkTextLength = max(try element.text().count, 0)
                if linkTextLength > 0 {
                    links.append(PendingTextLink(start: start, length: linkTextLength, url: url))
                }
            }
            currentLinkURL = previousLinkURL
        }

        private func parseRuby(_ element: Element) throws {
            let rubyText = try element.children()
                .array()
                .filter { $0.tagName().lowercased() == "rt" }
                .map { try $0.text() }
                .joined()
                .threadRoutingTrimmedNonEmpty
            let baseText = try element.getChildNodes()
                .filter { node in
                    guard let childElement = node as? Element else { return true }
                    return childElement.tagName().lowercased() != "rt"
                }
                .map { node -> String in
                    if let textNode = node as? TextNode {
                        return textNode.text()
                    }
                    if let childElement = node as? Element {
                        return try childElement.text()
                    }
                    return ""
                }
                .joined()
                .threadRoutingTrimmedNonEmpty

            guard let baseText, let rubyText else {
                try parseChildren(of: element)
                return
            }

            let start = text.count
            appendText(baseText)
            rubies.append(
                PendingRubyText(
                    start: start,
                    length: baseText.count,
                    baseText: baseText,
                    rubyText: rubyText
                )
            )
        }

        private func appendQuote(from element: Element) throws {
            commitText()
            appendBlock(
                .quote(try ForumThreadHTMLBlockParser.parseBlocks(fromHTML: try quoteContentHTML(from: element))),
                seed: "quote-\(try element.text().prefix(32))"
            )
        }

        private func quoteContentHTML(from element: Element) throws -> String {
            guard element.tagName().lowercased() != "blockquote" else {
                return try element.html()
            }

            let directChildren = element.children().array()
            let blockquoteChildren = directChildren.filter { $0.tagName().lowercased() == "blockquote" }
            let hasOnlyWhitespaceOutsideBlockquote = element.getChildNodes().allSatisfy { node in
                if let childElement = node as? Element {
                    return childElement.tagName().lowercased() == "blockquote"
                        || childElement.tagName().lowercased() == "br"
                }
                if let textNode = node as? TextNode {
                    return textNode.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return true
            }

            if blockquoteChildren.count == 1, hasOnlyWhitespaceOutsideBlockquote {
                return try blockquoteChildren[0].html()
            }

            return try element.html()
        }

        private func appendImage(from element: Element) throws {
            let rawSource = try element.attr("file").threadRoutingTrimmedNonEmpty
                ?? element.attr("zoomfile").threadRoutingTrimmedNonEmpty
                ?? element.attr("src").threadRoutingTrimmedNonEmpty
            guard let rawSource,
                  !rawSource.lowercased().contains("none.gif"),
                  let url = HTMLTextExtractor.absoluteURL(from: rawSource) else {
                return
            }

            commitText()
            let lowercased = url.absoluteString.lowercased()
            appendBlock(
                .image(
                    ForumThreadImageBlock(
                        url: url,
                        altText: try element.attr("alt"),
                        linkURL: currentLinkURL,
                        isEmoticon: lowercased.contains("/static/image/smiley/")
                            || lowercased.contains("static/image/smiley/")
                            || lowercased.contains("/smiley/")
                    )
                ),
                seed: "image-\(url.absoluteString)"
            )
        }

        private func attachment(from element: Element) throws -> ForumThreadAttachmentBlock? {
            guard let link = try element.select("a[href]").first(),
                  let url = HTMLTextExtractor.absoluteURL(from: try link.attr("href")) else {
                return nil
            }
            let fileName = try link.select(".link").first()?.text().threadRoutingTrimmedNonEmpty
                ?? link.select(".tit").first()?.ownText().threadRoutingTrimmedNonEmpty
                ?? link.text().split(separator: "\n").map(String.init).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                    .threadRoutingTrimmedNonEmpty
            guard let fileName else { return nil }

            let metadata = try link.select("p").array()
                .compactMap { try $0.text().threadRoutingTrimmedNonEmpty }
            return ForumThreadAttachmentBlock(
                url: url,
                iconURL: try link.select("img[src]").first().flatMap { HTMLTextExtractor.absoluteURL(from: try $0.attr("src")) },
                fileName: fileName,
                uploadInfo: metadata.first,
                statInfo: metadata.dropFirst().first
            )
        }

        private func parseChildren(of element: Element) throws {
            for child in element.getChildNodes() {
                try parse(node: child)
            }
        }

        private func withTextStyle(_ style: ForumThreadTextStyle, parse: () throws -> Void) throws {
            let previousStyle = currentStyle
            currentStyle = previousStyle.merged(with: style)
            try parse()
            currentStyle = previousStyle
        }

        private func appendTextNodeText(_ value: String) {
            for character in value {
                switch character {
                case "\u{00A0}":
                    appendText("\u{3000}")
                case " ", "\n", "\t", "\u{000C}":
                    appendCollapsibleSpace()
                default:
                    appendText(String(character))
                }
            }
        }

        private func appendText(_ value: String) {
            let decoded = HTMLTextExtractor.decodeHTMLEntities(value)
            guard !decoded.isEmpty else { return }
            let start = text.count
            text += decoded
            appendCurrentStyleRun(start: start, length: decoded.count)
        }

        private func appendLineBreak(maxConsecutive: Int = 2, explicit: Bool = false) {
            guard !text.isEmpty || explicit else { return }
            let trailing = text.reversed().prefix(while: { $0 == "\n" }).count
            if trailing < maxConsecutive {
                text += "\n"
            }
        }

        private func appendCollapsibleSpace() {
            guard let last = text.last else { return }
            if last != " ", last != "\n", last != "\u{3000}" {
                text += " "
            }
        }

        private func commitText() {
            let normalized = ForumThreadHTMLBlockParser.normalizeCommittedText(text)
            guard !normalized.isEmpty else {
                text = ""
                links = []
                styleRuns = []
                rubies = []
                return
            }

            let leadingTrimCount = text.prefix(while: \.isWhitespace).count
            let maxLength = normalized.count
            let blockLinks = links.compactMap { link -> ForumThreadTextLink? in
                let shiftedStart = max(0, link.start - leadingTrimCount)
                guard shiftedStart < maxLength else { return nil }
                let length = min(link.length, maxLength - shiftedStart)
                guard length > 0 else { return nil }
                return ForumThreadTextLink(start: shiftedStart, length: length, url: link.url)
            }
            let blockStyleRuns = styleRuns.compactMap { run -> ForumThreadTextStyleRun? in
                let shiftedStart = max(0, run.start - leadingTrimCount)
                guard shiftedStart < maxLength else { return nil }
                let length = min(run.length, maxLength - shiftedStart)
                guard length > 0 else { return nil }
                return ForumThreadTextStyleRun(start: shiftedStart, length: length, style: run.style)
            }
            let blockRubies = rubies.compactMap { ruby -> ForumThreadRubyText? in
                let shiftedStart = ruby.start - leadingTrimCount
                guard shiftedStart >= 0, shiftedStart + ruby.length <= maxLength else { return nil }
                return ForumThreadRubyText(
                    start: shiftedStart,
                    length: ruby.length,
                    baseText: ruby.baseText,
                    rubyText: ruby.rubyText
                )
            }
            appendBlock(
                .text(
                    ForumThreadTextBlock(
                        text: normalized,
                        alignment: currentAlignment,
                        links: blockLinks,
                        styleRuns: blockStyleRuns,
                        rubies: blockRubies
                    )
                ),
                seed: "text-\(normalized.prefix(64))"
            )
            text = ""
            links = []
            styleRuns = []
            rubies = []
        }

        private func withTextAlignment(
            _ alignment: ForumThreadTextAlignment,
            parse: () throws -> Void
        ) throws {
            let previousAlignment = currentAlignment
            if alignment != previousAlignment {
                commitText()
                currentAlignment = alignment
            }
            try parse()
            if alignment != previousAlignment {
                commitText()
                currentAlignment = previousAlignment
            }
        }

        private func textAlignment(from element: Element) throws -> ForumThreadTextAlignment? {
            switch try element.attr("align").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "center":
                return .center
            case "right":
                return .right
            case "left":
                return .left
            default:
                return nil
            }
        }

        private func appendCurrentStyleRun(start: Int, length: Int) {
            guard length > 0, !currentStyle.isEmpty else { return }
            if var last = styleRuns.last,
               last.start + last.length == start,
               last.style == currentStyle {
                last.length += length
                styleRuns[styleRuns.count - 1] = last
            } else {
                styleRuns.append(PendingTextStyleRun(start: start, length: length, style: currentStyle))
            }
        }

        private func appendBlock(_ kind: ForumThreadContentBlockKind, seed: String) {
            let id = "\(blockCounter)-\(Self.stableHash(seed))"
            blockCounter += 1
            blocks.append(ForumThreadContentBlock(id: id, kind: kind))
        }

        private static func stableHash(_ value: String) -> String {
            var hash: UInt64 = 5_381
            for byte in value.utf8 {
                hash = ((hash << 5) &+ hash) &+ UInt64(byte)
            }
            return String(hash, radix: 16)
        }

        private func textStyle(fromFontElement element: Element) throws -> ForumThreadTextStyle {
            var style = ForumThreadTextStyle()
            if let color = Self.normalizedColorHex(try element.attr("color")) {
                style.foregroundHex = color
            }
            if let fontSize = Self.relativeFontSize(fromHTMLSize: try element.attr("size")) {
                style.relativeFontSize = fontSize
            }
            style = style.merged(with: textStyle(fromStyleAttribute: try element.attr("style")))
            return style
        }

        private func textStyle(fromStyleAttribute styleAttribute: String) -> ForumThreadTextStyle {
            let declarations = Self.styleDeclarations(from: styleAttribute)
            return ForumThreadTextStyle(
                foregroundHex: declarations["color"].flatMap(Self.normalizedColorHex),
                backgroundHex: declarations["background-color"].flatMap(Self.normalizedColorHex),
                relativeFontSize: declarations["font-size"].flatMap(Self.relativeFontSize(fromCSSFontSize:))
            )
        }

        private static func styleDeclarations(from styleAttribute: String) -> [String: String] {
            var declarations: [String: String] = [:]
            for declaration in styleAttribute.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty {
                    declarations[key] = value
                }
            }
            return declarations
        }

        private static func relativeFontSize(fromHTMLSize rawValue: String) -> Double? {
            switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1": 0.75
            case "2": 0.875
            case "3": 1
            case "4": 1.125
            case "5": 1.5
            case "6": 2
            case "7": 3
            default: nil
            }
        }

        private static func relativeFontSize(fromCSSFontSize rawValue: String) -> Double? {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*(px|pt|em)$"#
            guard let match = HTMLTextExtractor.firstMatch(pattern: pattern, in: value).map({ Array($0.dropFirst()) }),
                  match.count == 2,
                  let number = Double(match[0]) else {
                return nil
            }
            switch match[1] {
            case "px":
                return number / 16
            case "pt":
                return (number * 4 / 3) / 16
            case "em":
                return number
            default:
                return nil
            }
        }

        private static func normalizedColorHex(_ rawValue: String) -> String? {
            let value = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("#") {
                return normalizedHexDigits(String(value.dropFirst()))
            }
            if value.hasPrefix("rgb") {
                return normalizedRGBHex(value)
            }
            return namedColorHex[value]
        }

        private static func normalizedHexDigits(_ digits: String) -> String? {
            let valid = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            guard digits.unicodeScalars.allSatisfy({ valid.contains($0) }) else { return nil }
            switch digits.count {
            case 3:
                let expanded = digits.map { "\($0)\($0)" }.joined()
                return "#\(expanded.uppercased())"
            case 6:
                return "#\(digits.uppercased())"
            default:
                return nil
            }
        }

        private static func normalizedRGBHex(_ value: String) -> String? {
            let body = value
                .replacingOccurrences(of: #"^rgba?\("#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\)$"#, with: "", options: .regularExpression)
            let components = body.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard components.count >= 3 else { return nil }
            let channels = components.prefix(3).compactMap(rgbChannel)
            guard channels.count == 3 else { return nil }
            return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        }

        private static func rgbChannel(_ rawValue: String) -> Int? {
            if rawValue.hasSuffix("%") {
                guard let value = Double(rawValue.dropLast()) else { return nil }
                return Int((min(max(value / 100, 0), 1) * 255).rounded())
            }
            guard let value = Double(rawValue) else { return nil }
            return Int(min(max(value, 0), 255).rounded())
        }

        private static let namedColorHex: [String: String] = [
            "red": "#FF0000",
            "blue": "#0000FF",
            "green": "#008000",
            "yellow": "#FFFF00",
            "black": "#000000",
            "white": "#FFFFFF",
            "grey": "#808080",
            "gray": "#808080",
            "darkgreen": "#006400",
            "darkblue": "#00008B",
            "darkred": "#8B0000",
            "darkorange": "#FF8C00",
            "darkgray": "#A9A9A9",
            "darkgrey": "#A9A9A9",
            "lightgray": "#D3D3D3",
            "lightgrey": "#D3D3D3",
            "lightblue": "#ADD8E6",
            "lightgreen": "#90EE90",
            "pink": "#FFC0CB",
            "orange": "#FFA500",
            "purple": "#800080",
            "skyblue": "#87CEEB",
            "palegreen": "#98FB98",
            "cyan": "#00FFFF",
            "magenta": "#FF00FF"
        ]
    }
}

private extension ForumThreadTextStyle {
    func merged(with other: ForumThreadTextStyle) -> ForumThreadTextStyle {
        ForumThreadTextStyle(
            isBold: isBold || other.isBold,
            isItalic: isItalic || other.isItalic,
            isUnderline: isUnderline || other.isUnderline,
            isStrikethrough: isStrikethrough || other.isStrikethrough,
            foregroundHex: other.foregroundHex ?? foregroundHex,
            backgroundHex: other.backgroundHex ?? backgroundHex,
            relativeFontSize: other.relativeFontSize ?? relativeFontSize
        )
    }
}
