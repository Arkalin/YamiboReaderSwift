import Foundation
import SwiftSoup

public enum ChapterCommentsHTMLParser {
    private static let filteredRatingReasons: Set<String> = [
        "你太可爱",
        "好萌好萌好萌",
        "我很赞同",
        "精品文章",
        "原创内容"
    ]

    public static func parseInitialPage(
        html: String,
        target: ReaderChapterCommentTarget
    ) throws -> ChapterCommentsPage {
        let document = try SwiftSoup.parse(html)
        var comments: [ChapterComment] = []
        comments.append(contentsOf: try postComments(in: document, target: target))
        comments.append(contentsOf: try ratingReasons(in: document, target: target))
        let replies = try samePageReplies(in: document, target: target)
        comments.append(contentsOf: replies.comments)
        return ChapterCommentsPage(
            target: target,
            comments: comments,
            isBoundaryClosed: replies.isBoundaryClosed,
            nextView: nextView(in: document, target: target, currentView: target.view, isBoundaryClosed: replies.isBoundaryClosed)
        )
    }

    public static func parseContinuationPage(
        html: String,
        target: ReaderChapterCommentTarget,
        view: Int
    ) throws -> ChapterCommentsPage {
        let document = try SwiftSoup.parse(html)
        let replies = try continuationReplies(in: document, target: target)
        return ChapterCommentsPage(
            target: target,
            comments: replies.comments,
            isBoundaryClosed: replies.isBoundaryClosed,
            nextView: nextView(in: document, target: target, currentView: view, isBoundaryClosed: replies.isBoundaryClosed)
        )
    }

    private static func postComments(
        in document: Document,
        target: ReaderChapterCommentTarget
    ) throws -> [ChapterComment] {
        let rows = try document.select("#comment_\(target.ownerPostID) .pstl")
        return try rows.array().enumerated().compactMap { offset, row in
            let author = try row.select(".psta a.xi2, .psta a.xw1, .psta a").first()?.text() ?? ""
            guard let bodyElement = try row.select(".psti").first() else { return nil }
            let metadata = try bodyElement.select(".xg1").first()?.text()
            try bodyElement.select(".xg1").remove()
            let body = normalizeText(try bodyElement.text())
            guard !body.isEmpty else { return nil }
            return ChapterComment(
                id: "\(target.ownerPostID):comment:\(offset)",
                source: .postComment,
                authorName: normalizeText(author),
                metadata: nilIfEmpty(normalizeText(metadata ?? "")),
                body: body,
                postID: target.ownerPostID
            )
        }
    }

    private static func ratingReasons(
        in document: Document,
        target: ReaderChapterCommentTarget
    ) throws -> [ChapterComment] {
        let rows = try document.select("[id=ratelog_\(target.ownerPostID)] tr")
        return try rows.array().enumerated().compactMap { offset, row in
            let cells = try row.select("td")
            let author = try cells.first()?.select("a").last()?.text() ?? ""
            let reason = normalizeRatingReason(try row.select("td.xg1").first()?.text() ?? "")
            guard !reason.isEmpty, !filteredRatingReasons.contains(reason) else {
                return nil
            }
            return ChapterComment(
                id: "\(target.ownerPostID):rating:\(offset)",
                source: .ratingReason,
                authorName: normalizeText(author),
                body: reason,
                postID: target.ownerPostID
            )
        }
    }

    private static func samePageReplies(
        in document: Document,
        target: ReaderChapterCommentTarget
    ) throws -> (comments: [ChapterComment], isBoundaryClosed: Bool) {
        let messageNodes = try document.select("[id^=postmessage_]").array()
        var foundTarget = false
        var comments: [ChapterComment] = []

        for message in messageNodes {
            guard let postID = postID(from: message) else { continue }
            if postID == target.ownerPostID {
                foundTarget = true
                continue
            }
            guard foundTarget else { continue }

            if isOwnerPost(message) {
                return (comments, true)
            }

            guard let body = try replyBody(from: message), !body.isEmpty else {
                continue
            }
            comments.append(
                ChapterComment(
                    id: "\(target.ownerPostID):reply:\(postID)",
                    source: .reply,
                    authorName: authorName(for: message),
                    body: body,
                    postID: postID
                )
            )
        }

        return (comments, false)
    }

    private static func continuationReplies(
        in document: Document,
        target: ReaderChapterCommentTarget
    ) throws -> (comments: [ChapterComment], isBoundaryClosed: Bool) {
        let messageNodes = try document.select("[id^=postmessage_]").array()
        var comments: [ChapterComment] = []

        for message in messageNodes {
            guard let postID = postID(from: message) else { continue }
            if isOwnerPost(message) {
                return (comments, true)
            }
            guard let body = try replyBody(from: message), !body.isEmpty else {
                continue
            }
            comments.append(
                ChapterComment(
                    id: "\(target.ownerPostID):reply:\(postID)",
                    source: .reply,
                    authorName: authorName(for: message),
                    body: body,
                    postID: postID
                )
            )
        }

        return (comments, false)
    }

    private static func replyBody(from message: Element) throws -> String? {
        let fragment = try SwiftSoup.parseBodyFragment(try message.html())
        guard let body = fragment.body() else { return nil }
        try body.select(".quote, blockquote, i").remove()
        let text = normalizeText(try body.text())
        return text.isEmpty ? nil : text
    }

    private static func isOwnerPost(_ message: Element) -> Bool {
        guard let container = postContainer(for: message) else {
            return false
        }
        if ((try? container.select("[title=楼主]").isEmpty()) == false) {
            return true
        }
        return false
    }

    private static func authorName(for message: Element) -> String {
        guard let container = postContainer(for: message) else {
            return ""
        }
        let selectors = [
            ".authi .author",
            ".authi a[href*=space-uid]",
            ".authi a",
            ".psta a.xi2",
            ".psta a"
        ]
        for selector in selectors {
            if let text = try? container.select(selector).first()?.text(),
               let normalized = nilIfEmpty(normalizeText(text)) {
                return normalized
            }
        }
        return ""
    }

    private static func postContainer(for element: Element) -> Element? {
        var current: Element? = element
        while let candidate = current {
            if let id = try? candidate.attr("id"),
               id.hasPrefix("post_") {
                return candidate
            }
            if ((try? candidate.select(".authi").isEmpty()) == false),
               ((try? candidate.select("[id^=postmessage_]").isEmpty()) == false) {
                return candidate
            }
            current = candidate.parent()
        }
        return nil
    }

    private static func postID(from element: Element) -> String? {
        let raw = (try? element.attr("id"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.hasPrefix("postmessage_") else { return nil }
        let value = raw.replacingOccurrences(of: "postmessage_", with: "")
        return value.isEmpty ? nil : value
    }

    private static func nextView(
        in document: Document,
        target: ReaderChapterCommentTarget,
        currentView: Int,
        isBoundaryClosed: Bool
    ) -> Int? {
        guard !isBoundaryClosed else { return nil }
        let request = ReaderPageRequest(threadURL: target.threadURL, view: currentView)
        let maxView = (try? ReaderHTMLDOMParser.parseMaxView(in: .init(document: document), request: request)) ?? currentView
        let next = currentView + 1
        return next <= maxView ? next : nil
    }

    private static func normalizeRatingReason(_ text: String) -> String {
        normalizeText(
            text
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{3000}", with: " ")
        )
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
