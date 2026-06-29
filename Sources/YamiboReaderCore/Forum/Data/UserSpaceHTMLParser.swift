import Foundation
import SwiftSoup

public enum UserSpaceHTMLParser {
    public static func parseProfile(from html: String, uidHint: String? = nil, titleHint: String? = nil) throws -> UserSpaceProfile {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let bodyText = ((try? document.body()?.text()) ?? "").normalizedUserSpaceText

        let uid = uidHint?.nilIfBlank
            ?? firstMatch(#"UID\s*[:：]?\s*(\d+)"#, in: bodyText)
            ?? firstUserID(in: document)
            ?? ""
        let username = firstNonBlank([
            try? document.select(".username, .mtit, h2, h1").first()?.text(),
            titleHint,
            try? document.title().replacingOccurrences(of: "-  百合会", with: "")
        ]) ?? L10n.string("user_space.unknown_user")
        let infoRows = parseInfoRows(in: document)

        return UserSpaceProfile(
            uid: uid,
            username: username,
            userGroup: infoRows.first(where: { $0.label.contains("用户组") || $0.label.contains("用戶組") })?.value,
            avatarURL: firstImageURL(in: document, selectors: [
                ".avatar img[src]",
                ".mimg img[src]",
                "img[src*='avatar']"
            ]),
            avatarBackgroundURL: firstImageURL(in: document, selectors: [
                ".space_bg img[src]",
                ".profile_bg img[src]",
                "img[src*='avatar_big']"
            ]),
            signature: firstNonBlank([
                try? document.select(".signature, .sign, .pf_l").first()?.text()
            ]),
            totalPoints: intAfterAny(labels: ["总积分", "總積分"], in: bodyText),
            points: plainPoints(in: bodyText),
            partner: intAfterAny(labels: ["对象", "對象"], in: bodyText),
            infoRows: infoRows
        )
    }

    public static func parseThreads(from html: String) throws -> UserSpaceThreadPage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        return UserSpaceThreadPage(
            threads: parseThreadSummaries(in: document),
            pageNavigation: parsePageNavigation(in: document)
        )
    }

    public static func parseReplies(from html: String) throws -> UserSpaceReplyPage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let links = (try? document.select("a[href*='viewthread'][href*='tid='], a[href*='thread-']")) ?? Elements()
        var replies: [UserSpaceReplyGroup] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let tid = threadID(from: url),
                  seen.insert(tid).inserted else {
                continue
            }
            let title = ((try? link.text()) ?? "").normalizedUserSpaceText
            guard !title.isEmpty else { continue }
            let container = nearestListContainer(for: link)
            replies.append(
                UserSpaceReplyGroup(
                    threadID: tid,
                    threadTitle: title,
                    threadURL: url,
                    excerpt: ((try? container?.text()) ?? "").normalizedUserSpaceText.nilIfBlank,
                    lastActivityText: firstDateText(in: container)
                )
            )
        }

        return UserSpaceReplyPage(replies: replies, pageNavigation: parsePageNavigation(in: document))
    }

    public static func parseBlogs(from html: String) throws -> UserSpaceBlogPage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let links = (try? document.select("a[href*='do=blog'][href*='id='], a[href*='blog-']")) ?? Elements()
        var blogs: [UserSpaceBlogSummary] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let blogID = blogID(from: url),
                  seen.insert(blogID).inserted else {
                continue
            }
            let title = ((try? link.text()) ?? "").normalizedUserSpaceText
            guard !title.isEmpty else { continue }
            let container = nearestListContainer(for: link)
            let text = ((try? container?.text()) ?? "").normalizedUserSpaceText
            blogs.append(
                UserSpaceBlogSummary(
                    blogID: blogID,
                    title: title,
                    url: url,
                    authorName: firstAuthorName(in: container),
                    authorID: firstUserID(in: container),
                    excerpt: text.nilIfBlank,
                    lastActivityText: firstDateText(in: container),
                    replyCount: intAfterAny(labels: ["回复", "回復"], in: text),
                    viewCount: intAfterAny(labels: ["查看", "浏览", "瀏覽"], in: text)
                )
            )
        }

        return UserSpaceBlogPage(blogs: blogs, pageNavigation: parsePageNavigation(in: document))
    }

    public static func parseFriends(from html: String) throws -> UserSpaceFriendPage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let containers = friendListContainers(in: document)
        let links = (try? containers.select("a[href*='mod=space'][href*='uid='], a[href*='space-uid-']")) ?? Elements()
        var friends: [UserSpaceFriendSummary] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let uid = userID(from: url),
                  seen.insert(uid).inserted else {
                continue
            }
            let name = ((try? link.text()) ?? "").normalizedUserSpaceText
            guard !name.isEmpty else { continue }
            let container = nearestListContainer(for: link)
            friends.append(
                UserSpaceFriendSummary(
                    uid: uid,
                    name: name,
                    avatarURL: firstImageURL(in: container, selectors: ["img[src]"]),
                    detail: ((try? container?.text()) ?? "").normalizedUserSpaceText.nilIfBlank,
                    privateMessageURL: firstActionURL(in: container, patterns: ["ac=pm", "op=showmsg", "sendpm"]),
                    deleteURL: firstActionURL(in: container, patterns: ["op=ignore", "op=delete", "ac=friend&op=delete"])
                )
            )
        }

        return UserSpaceFriendPage(friends: friends, pageNavigation: parsePageNavigation(in: document))
    }

    public static func parsePrivateMessageList(from html: String) throws -> UserSpacePrivateMessagePage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let links = (try? document.select("a[href*='op=showmsg'][href*='touid='], a[href*='ac=pm'][href*='touid=']")) ?? Elements()
        var messages: [UserSpacePrivateMessageSummary] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let uid = queryValue("touid", in: url) ?? queryValue("uid", in: url),
                  seen.insert(uid).inserted else {
                continue
            }

            let container = nearestListContainer(for: link)
            let text = ((try? container?.text()) ?? (try? link.text()) ?? "").normalizedUserSpaceText
            let name = firstNonBlank([
                firstUserName(uid: uid, in: container),
                try? link.text()
            ]) ?? L10n.string("user_space.unknown_user")
            let title = firstNonBlank([
                try? container?.select(".title, .subject, h3, h4").first()?.text(),
                try? link.text()
            ]) ?? name

            messages.append(
                UserSpacePrivateMessageSummary(
                    uid: uid,
                    name: name,
                    avatarURL: firstImageURL(in: container, selectors: ["img[src*='avatar']", ".avatar img[src]", ".mimg img[src]", "img[src]"]),
                    title: title,
                    message: privateMessageListPreview(text: text, title: title, name: name),
                    timeText: firstDateText(in: container),
                    unreadCount: firstUnreadCount(in: container)
                )
            )
        }

        return UserSpacePrivateMessagePage(
            messages: messages,
            unreadCount: unreadCount(in: document),
            pageNavigation: parsePageNavigation(in: document)
        )
    }

    public static func parseNotices(from html: String) throws -> UserSpaceNoticePage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let containers = noticeContainers(in: document)
        var notices: [UserSpaceNoticeSummary] = []
        var seen = Set<String>()

        for container in containers {
            let content = noticeContentElement(in: container) ?? container
            let contentHTML = ((try? content.html()) ?? "").nilIfBlank ?? ((try? container.html()) ?? "")
            let contentText = ((try? content.text()) ?? "").normalizedUserSpaceText
            guard !contentText.isEmpty else { continue }

            let noticeID = noticeID(in: container) ?? [firstDateText(in: container), contentText].compactMap { $0 }.joined(separator: "|")
            guard !noticeID.isEmpty, seen.insert(noticeID).inserted else { continue }
            let avatarURL = firstImageURL(in: container, selectors: ["img[src*='avatar']", ".avatar img[src]", ".mimg img[src]", "img[src]"])

            notices.append(
                UserSpaceNoticeSummary(
                    noticeID: noticeID,
                    avatarURL: avatarURL,
                    userID: firstUserID(in: container) ?? avatarURL.flatMap(userIDFromAvatarURL),
                    contentHTML: contentHTML,
                    contentText: contentText,
                    quote: firstNonBlank([
                        try? container.select("blockquote, .quote, .notice_quote").first()?.text()
                    ]),
                    timeText: firstDateText(in: container)
                )
            )
        }

        return UserSpaceNoticePage(notices: notices, pageNavigation: parsePageNavigation(in: document))
    }

    public static func parseAddFriendForm(from html: String, uid: String, nameHint: String? = nil) throws -> UserSpaceAddFriendForm {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        guard let formHash = parseFormHash(in: document, html: html) else {
            throw YamiboError.parsingFailed(context: L10n.string("context.user_space_add_friend"))
        }

        return UserSpaceAddFriendForm(
            uid: uid,
            name: firstNonBlank([
                try? document.select(".username, .mtit, h3, h2, a[href*='uid=\(uid)']").first()?.text(),
                nameHint
            ]),
            avatarURL: firstImageURL(in: document, selectors: [
                ".avatar img[src]",
                ".mimg img[src]",
                "img[src*='avatar']"
            ]),
            formHash: formHash,
            options: parseAddFriendOptions(in: document)
        )
    }

    public static func parseAddFriendResult(from html: String) throws -> String {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let message = (
            (try? document.select(".jump_c, .alert_info, .messagetext, .showmessage, .wp, body").first()?.text())
                ?? ""
        ).normalizedUserSpaceText

        if message.contains("请先登录") || message.contains("請先登錄") || message.contains("请登录") {
            throw YamiboError.notAuthenticated
        }
        if message.contains("失败") || message.contains("失敗") || message.contains("错误") || message.contains("錯誤") {
            throw YamiboError.underlying(message)
        }
        if message.isEmpty {
            throw YamiboError.parsingFailed(context: L10n.string("context.user_space_add_friend"))
        }
        return message
    }

    public static func parsePrivateMessagePage(from html: String, toUID: String, titleHint: String? = nil) throws -> PrivateMessagePage {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let normalizedToUID = toUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let toName = firstNonBlank([
            titleHint,
            firstUserName(uid: normalizedToUID, in: document),
            try? document.select(".username, .mtit, h2, h1").first()?.text()
        ])
        let title = firstNonBlank([
            try? document.select(".header h2, .mtit, h1, h2").first()?.text(),
            toName.map { L10n.string("private_message.chat_with", $0) },
            try? document.title().replacingOccurrences(of: "-  百合会", with: "")
        ]) ?? L10n.string("private_message.title")
        let formHash = parseFormHash(in: document, html: html)
        let privateMessageID = parsePrivateMessageID(in: document, html: html) ?? "0"

        return PrivateMessagePage(
            title: title,
            privateMessageID: privateMessageID,
            toUID: normalizedToUID,
            toName: toName,
            formHash: formHash,
            messages: parsePrivateMessages(in: document, toUID: normalizedToUID, toName: toName),
            pageNavigation: parsePageNavigation(in: document)
        )
    }

    public static func parsePrivateMessageSendResult(from html: String) throws -> String {
        try validate(html)
        let document = try SwiftSoup.parse(html, YamiboRoute.baseURL.absoluteString)
        let message = (
            (try? document.select(".jump_c, .alert_info, .messagetext, .showmessage, .wp, body").first()?.text())
                ?? ""
        ).normalizedUserSpaceText

        if message.contains("请先登录") || message.contains("請先登錄") || message.contains("请登录") {
            throw YamiboError.notAuthenticated
        }
        if message.contains("失败") || message.contains("失敗") || message.contains("错误") || message.contains("錯誤") {
            throw YamiboError.underlying(message)
        }
        if message.isEmpty {
            throw YamiboError.parsingFailed(context: L10n.string("context.private_message"))
        }
        return message
    }

    private static func validate(_ html: String) throws {
        if ReaderHTMLParser.isNotAuthenticated(html) {
            throw YamiboError.notAuthenticated
        }
        if ReaderHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }
    }

    private static func parseThreadSummaries(in document: Document) -> [ForumThreadSummary] {
        let links = (try? document.select("a[href*='viewthread'][href*='tid='], a[href*='thread-']")) ?? Elements()
        var threads: [ForumThreadSummary] = []
        var seen = Set<String>()

        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let tid = threadID(from: url),
                  seen.insert(tid).inserted else {
                continue
            }
            let title = ((try? link.text()) ?? "").normalizedUserSpaceText
            guard !title.isEmpty else { continue }
            let container = nearestListContainer(for: link)
            let text = ((try? container?.text()) ?? "").normalizedUserSpaceText
            threads.append(
                ForumThreadSummary(
                    tid: tid,
                    title: title,
                    url: url,
                    authorName: firstAuthorName(in: container),
                    authorID: firstUserID(in: container),
                    authorAvatarURL: firstImageURL(in: container, selectors: ["img[src*='avatar']", "img[src]"]),
                    description: text.nilIfBlank,
                    replyCount: intAfterAny(labels: ["回复", "回復"], in: text),
                    viewCount: intAfterAny(labels: ["查看", "浏览", "瀏覽"], in: text),
                    lastActivityText: firstDateText(in: container)
                )
            )
        }

        return threads
    }

    private static func parseInfoRows(in document: Document) -> [UserSpaceInfoRow] {
        let rows = (try? document.select("li, tr, .pbm, .pf_l li, .profile_info li")) ?? Elements()
        var info: [UserSpaceInfoRow] = []
        var seen = Set<String>()

        for row in rows {
            let text = ((try? row.text()) ?? "").normalizedUserSpaceText
            guard let separator = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let label = String(text[..<separator]).normalizedUserSpaceText
            let value = String(text[text.index(after: separator)...]).normalizedUserSpaceText
            guard !label.isEmpty, !value.isEmpty else { continue }
            let url = (try? row.select("a[href]").first()?.attr("href")).flatMap { HTMLTextExtractor.absoluteURL(from: $0) }
            let item = UserSpaceInfoRow(label: label, value: value, url: url)
            guard seen.insert(item.id).inserted else { continue }
            info.append(item)
        }

        return info
    }

    private static func parseAddFriendOptions(in document: Document) -> [UserSpaceAddFriendOption] {
        let options = (try? document.select("select[name=gid] option, select[name=groupid] option, select[name=group] option")) ?? Elements()
        var result: [UserSpaceAddFriendOption] = []
        var seen = Set<Int>()

        for option in options {
            let rawID = ((try? option.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = Int(rawID), seen.insert(id).inserted else { continue }
            let name = ((try? option.text()) ?? "").normalizedUserSpaceText
            guard !name.isEmpty else { continue }
            result.append(UserSpaceAddFriendOption(id: id, name: name))
        }

        return result
    }

    private static func parseFormHash(in document: Document, html: String) -> String? {
        if let value = try? document.select("input[name=formhash]").first()?.attr("value"),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HTMLTextExtractor.firstMatch(pattern: #"formhash=([A-Za-z0-9]+)"#, in: html)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func parsePrivateMessages(in document: Document, toUID: String, toName: String?) -> [PrivateMessage] {
        let containers = privateMessageContainers(in: document)
        var messages: [PrivateMessage] = []
        var seen = Set<String>()

        for container in containers {
            let content = privateMessageContentElement(in: container) ?? container
            let contentHTML = ((try? content.html()) ?? "").nilIfBlank ?? ((try? container.html()) ?? "")
            let contentText = ((try? content.text()) ?? "").normalizedUserSpaceText
            guard !contentText.isEmpty else { continue }

            let user = privateMessageUser(in: container, toUID: toUID, toName: toName)
            let className = ((try? container.className()) ?? "").lowercased()
            let kind: PrivateMessageKind = if user.uid == toUID {
                .other
            } else if className.contains("self") || className.contains("right") || className.contains("me") || className.contains("mine") {
                .me
            } else {
                .other
            }
            let message = PrivateMessage(
                messageID: privateMessageItemID(in: container),
                kind: kind,
                author: user,
                postedAtText: firstDateText(in: container),
                contentHTML: contentHTML,
                contentText: contentText
            )
            guard seen.insert(message.id).inserted else { continue }
            messages.append(message)
        }

        return messages
    }

    private static func privateMessageContainers(in document: Document) -> Elements {
        let scoped = (try? document.select([
            ".pm_msg",
            ".pmb",
            ".pmlist li",
            ".pm_list li",
            ".messageitem",
            ".message_item",
            "li[id^=pm_]",
            "div[id^=pm_]",
            ".bbda"
        ].joined(separator: ","))) ?? Elements()
        if !scoped.isEmpty {
            return scoped
        }
        return (try? document.select("li, .cl")) ?? Elements()
    }

    private static func privateMessageContentElement(in container: Element) -> Element? {
        for selector in [".pmcontent", ".message", ".content", ".t_f", ".txt", "blockquote"] {
            if let element = try? container.select(selector).last() {
                return element
            }
        }
        return nil
    }

    private static func privateMessageUser(in container: Element, toUID: String, toName: String?) -> PrivateMessageUser {
        let link = firstUserLink(in: container)
        let href = (try? link?.attr("href")).flatMap { HTMLTextExtractor.absoluteURL(from: $0) }
        let uid = href.flatMap(userID(from:))
        let name = firstNonBlank([
            try? link?.text(),
            uid == toUID ? toName : nil,
            uid == nil ? toName : nil
        ]) ?? L10n.string("private_message.me")
        return PrivateMessageUser(
            uid: uid,
            name: name,
            avatarURL: firstImageURL(in: container, selectors: ["img[src*='avatar']", ".avatar img[src]", ".mimg img[src]", "img[src]"])
        )
    }

    private static func firstUserLink(in element: Element) -> Element? {
        try? element.select("a[href*='uid='], a[href*='space-uid-']").first()
    }

    private static func firstUserName(uid: String, in document: Document) -> String? {
        let links = (try? document.select("a[href*='uid=\(uid)'], a[href*='space-uid-\(uid)']")) ?? Elements()
        for link in links {
            if let name = (try? link.text())?.normalizedUserSpaceText.nilIfBlank {
                return name
            }
        }
        return nil
    }

    private static func firstUserName(uid: String, in element: Element?) -> String? {
        guard let element else { return nil }
        let links = (try? element.select("a[href*='uid=\(uid)'], a[href*='space-uid-\(uid)']")) ?? Elements()
        for link in links {
            if let name = (try? link.text())?.normalizedUserSpaceText.nilIfBlank {
                return name
            }
        }
        return nil
    }

    private static func privateMessageItemID(in container: Element) -> String? {
        for attribute in ["data-id", "data-pmid", "id"] {
            if let value = (try? container.attr(attribute))?.nilIfBlank {
                return HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: value)?.first ?? value
            }
        }
        return nil
    }

    private static func parsePrivateMessageID(in document: Document, html: String) -> String? {
        if let value = try? document.select("input[name=pmid]").first()?.attr("value"),
           let normalized = value.nilIfBlank {
            return normalized
        }
        let links = (try? document.select("form[action*='pmid='], a[href*='pmid=']")) ?? Elements()
        for link in links {
            let rawURL = ((try? link.attr("action")) ?? (try? link.attr("href")) ?? "")
            guard let url = HTMLTextExtractor.absoluteURL(from: rawURL),
                  let pmid = queryValue("pmid", in: url) else {
                continue
            }
            return pmid
        }
        return HTMLTextExtractor.firstMatch(pattern: #"pmid=([A-Za-z0-9]+)"#, in: html)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func friendListContainers(in document: Document) -> Elements {
        let scoped = (try? document.select(".friendlist, .buddy, .ulist, .ml, .buddylist, #friend_ul")) ?? Elements()
        if !scoped.isEmpty {
            return scoped
        }
        return (try? document.select("body")) ?? Elements()
    }

    private static func noticeContainers(in document: Document) -> Elements {
        let scoped = (try? document.select([
            "li[id^=notice_]",
            "div[id^=notice_]",
            ".notice li",
            ".nts li",
            ".ntc li",
            ".xld li",
            ".bbda"
        ].joined(separator: ","))) ?? Elements()
        if !scoped.isEmpty {
            return scoped
        }
        return (try? document.select("li, .cl")) ?? Elements()
    }

    private static func noticeContentElement(in container: Element) -> Element? {
        for selector in [".ntc_body", ".notice_body", ".content", ".detail", ".xw0", ".txt"] {
            if let element = try? container.select(selector).first() {
                return element
            }
        }
        return nil
    }

    private static func noticeID(in container: Element) -> String? {
        for attribute in ["data-id", "data-notice-id", "id"] {
            if let value = (try? container.attr(attribute))?.nilIfBlank {
                return HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: value)?.first ?? value
            }
        }
        if let href = try? container.select("a[href*='noticeid=']").first()?.attr("href"),
           let url = HTMLTextExtractor.absoluteURL(from: href),
           let noticeID = queryValue("noticeid", in: url) {
            return noticeID
        }
        return nil
    }

    private static func privateMessageListPreview(text: String, title: String, name: String) -> String {
        var preview = text
        for prefix in [title, name] where !prefix.isEmpty {
            if preview.hasPrefix(prefix) {
                preview = String(preview.dropFirst(prefix.count)).normalizedUserSpaceText
            }
        }
        return preview.nilIfBlank ?? title
    }

    private static func unreadCount(in document: Document) -> Int? {
        let text = ((try? document.body()?.text()) ?? "").normalizedUserSpaceText
        return HTMLTextExtractor.firstMatch(pattern: #"(?:未读|未讀)\s*[:：]?\s*(\d+)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init)
    }

    private static func firstUnreadCount(in element: Element?) -> Int? {
        guard let element else { return nil }
        let text = ((try? element.text()) ?? "").normalizedUserSpaceText
        if let value = HTMLTextExtractor.firstMatch(pattern: #"(?:未读|未讀|新消息)\s*[:：]?\s*(\d+)"#, in: text)?
            .dropFirst()
            .first
            .flatMap(Int.init) {
            return value
        }
        for selector in [".unread", ".badge", ".num"] {
            if let value = try? element.select(selector).first()?.text(),
               let number = HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: value)?.first.flatMap(Int.init) {
                return number
            }
        }
        return nil
    }

    private static func userIDFromAvatarURL(_ url: URL) -> String? {
        let normalized = url.absoluteString.replacingOccurrences(of: "\\", with: "/")
        guard let match = HTMLTextExtractor.firstMatch(pattern: #"/avatar/(\d{3})/(\d{2})/(\d{2})/(\d{2})_avatar"#, in: normalized) else {
            return nil
        }
        let rawUID = match.dropFirst().joined()
        return Int(rawUID).map(String.init)
    }

    private static func parsePageNavigation(in document: Document) -> ForumPageNavigation? {
        guard let pager = try? document.select(".pg").first() else { return nil }
        let currentText = ((try? pager.select("strong").first()?.text()) ?? "").normalizedUserSpaceText
        let currentPage = Int(currentText) ?? 1
        let pagerText = ((try? pager.text()) ?? "").normalizedUserSpaceText
        let totalPages = HTMLTextExtractor.firstMatch(pattern: #"共\s*(\d+)\s*页"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
            ?? HTMLTextExtractor.matches(pattern: #"page=(\d+)"#, in: (try? pager.html()) ?? "")
            .compactMap { $0.dropFirst().first.flatMap(Int.init) }
            .max()
        return ForumPageNavigation(currentPage: currentPage, totalPages: totalPages)
    }

    private static func nearestListContainer(for element: Element) -> Element? {
        var node: Element? = element
        while let current = node {
            if ["li", "tr", "dd", "div"].contains(current.tagName()) {
                return current
            }
            node = current.parent()
        }
        return element
    }

    private static func firstImageURL(in element: Element?, selectors: [String]) -> URL? {
        guard let element else { return nil }
        for selector in selectors {
            if let href = try? element.select(selector).first()?.attr("src"),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
        }
        return nil
    }

    private static func firstImageURL(in document: Document, selectors: [String]) -> URL? {
        for selector in selectors {
            if let href = try? document.select(selector).first()?.attr("src"),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
        }
        return nil
    }

    private static func firstActionURL(in element: Element?, patterns: [String]) -> URL? {
        guard let element else { return nil }
        let links = (try? element.select("a[href]")) ?? Elements()
        for link in links {
            let href = ((try? link.attr("href")) ?? "")
                .replacingOccurrences(of: "&amp;", with: "&")
            let text = ((try? link.text()) ?? "").normalizedUserSpaceText
            if patterns.contains(where: { href.contains($0) || text.contains($0) }),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
            if patterns.contains("ac=pm"), (text.contains("发消息") || text.contains("發消息") || text.contains("短消息")),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
            if patterns.contains("op=delete"), (text.contains("删除") || text.contains("刪除") || text.contains("解除")),
               let url = HTMLTextExtractor.absoluteURL(from: href) {
                return url
            }
        }
        return nil
    }

    private static func firstAuthorName(in element: Element?) -> String? {
        firstNonBlank([
            try? element?.select(".mmc, a[href*='uid=']").first()?.text()
        ])
    }

    private static func firstUserID(in document: Document) -> String? {
        let links = (try? document.select("a[href*='uid='], a[href*='space-uid-']")) ?? Elements()
        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let uid = userID(from: url) else {
                continue
            }
            return uid
        }
        return nil
    }

    private static func firstUserID(in element: Element?) -> String? {
        guard let element else { return nil }
        let links = (try? element.select("a[href*='uid='], a[href*='space-uid-']")) ?? Elements()
        for link in links {
            guard let url = HTMLTextExtractor.absoluteURL(from: (try? link.attr("href")) ?? ""),
                  let uid = userID(from: url) else {
                continue
            }
            return uid
        }
        return nil
    }

    private static func firstDateText(in element: Element?) -> String? {
        let text = ((try? element?.text()) ?? "").normalizedUserSpaceText
        return HTMLTextExtractor.firstMatch(pattern: #"\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:\s+\d{1,2}:\d{2})?"#, in: text)?
            .first?
            .nilIfBlank
    }

    private static func threadID(from url: URL) -> String? {
        queryValue("tid", in: url)
            ?? HTMLTextExtractor.firstMatch(pattern: #"thread-(\d+)-"#, in: url.absoluteString)?.dropFirst().first
    }

    private static func userID(from url: URL) -> String? {
        queryValue("uid", in: url)
            ?? HTMLTextExtractor.firstMatch(pattern: #"space-uid-(\d+)"#, in: url.absoluteString)?.dropFirst().first
    }

    private static func blogID(from url: URL) -> String? {
        queryValue("id", in: url)
            ?? HTMLTextExtractor.firstMatch(pattern: #"blog-(\d+)-"#, in: url.absoluteString)?.dropFirst().first
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value?
            .nilIfBlank
    }

    private static func intAfterAny(labels: [String], in text: String) -> Int? {
        for label in labels {
            if let value = HTMLTextExtractor.firstMatch(pattern: #"\#(label)\s*[:：]?\s*(\d+)"#, in: text)?
                .dropFirst()
                .last
                .flatMap(Int.init) {
                return value
            }
        }
        return nil
    }

    private static func plainPoints(in text: String) -> Int? {
        for pattern in [#"(?:^|\s)积分\s*[:：]?\s*(\d+)"#, #"(?:^|\s)積分\s*[:：]?\s*(\d+)"#] {
            if let value = HTMLTextExtractor.firstMatch(pattern: pattern, in: text)?
                .dropFirst()
                .first
                .flatMap(Int.init) {
                return value
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: pattern, in: text)?
            .dropFirst()
            .first?
            .nilIfBlank
    }

    private static func firstNonBlank(_ values: [String?]) -> String? {
        values.compactMap { $0?.normalizedUserSpaceText.nilIfBlank }.first
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedUserSpaceText: String {
        HTMLTextExtractor.decodeHTMLEntities(self)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
