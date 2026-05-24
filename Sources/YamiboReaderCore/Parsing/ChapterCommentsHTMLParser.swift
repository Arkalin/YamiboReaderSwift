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
        return ChapterCommentsPage(target: target, comments: comments, isBoundaryClosed: true)
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
