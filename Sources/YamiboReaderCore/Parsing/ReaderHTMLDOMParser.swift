import Foundation
import SwiftSoup

enum ReaderHTMLDOMParser {
    struct Context {
        let document: Document
    }

    struct ParsedMessage {
        let text: String
        let imageURLs: [URL]
        let chapterTitle: String?
    }

    static func parse(html: String) throws -> Context {
        Context(document: try SwiftSoup.parse(html))
    }

    static func messageNodes(in context: Context) throws -> [Element] {
        let nodes = try context.document.select(".message, [id*=postmessage]")
        var uniqueNodes: [Element] = []
        for node in nodes {
            if uniqueNodes.contains(where: { $0 === node }) {
                continue
            }
            uniqueNodes.append(node)
        }
        return uniqueNodes
    }

    static func parseMessages(in context: Context) throws -> [ParsedMessage] {
        try messageNodes(in: context).map(parseMessage)
    }

    static func parseTitle(in context: Context) throws -> String? {
        let title = try context.document.title().trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func parseOnlyAuthorID(in context: Context, request: ReaderPageRequest) throws -> String? {
        guard let threadID = ReaderHTMLParser.extractThreadID(from: request.threadURL) else {
            return nil
        }

        for link in try context.document.select("a[href]") {
            let href = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = urlComponents(from: href),
                  isSameThreadLink(components: components, href: href, threadID: threadID),
                  let authorID = components.queryItems?.first(where: { $0.name == "authorid" })?.value,
                  !authorID.isEmpty else {
                continue
            }
            return authorID
        }

        return nil
    }

    static func parseMaxView(in context: Context, request: ReaderPageRequest) throws -> Int {
        let fallback = max(1, request.view)
        guard let threadID = ReaderHTMLParser.extractThreadID(from: request.threadURL) else {
            return fallback
        }

        var pages = Set([fallback])

        for option in try context.document.select("select option[value]") {
            let value = try option.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
            if let page = Int(value), page > 0 {
                pages.insert(page)
            }
        }

        for link in try context.document.select("a[href]") {
            let href = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = urlComponents(from: href),
                  isSameThreadLink(components: components, href: href, threadID: threadID),
                  let page = pageNumber(from: components, href: href, threadID: threadID) else {
                continue
            }
            pages.insert(page)
        }

        return pages.max() ?? fallback
    }

    private static func parseMessage(_ element: Element) throws -> ParsedMessage {
        let fragmentHTML = try element.html()
        let fragment = try SwiftSoup.parseBodyFragment(fragmentHTML)
        guard let body = fragment.body() else {
            return ParsedMessage(text: "", imageURLs: [], chapterTitle: nil)
        }

        try body.select("i").remove()
        let text = try readableText(from: body)
        let chapterTitle = ReaderChapterTitleNormalizer.normalize(
            text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
                .map { String($0.prefix(30)) }
        )

        var imageURLs: [URL] = []
        for image in try body.select("img") {
            let raw = try imageSource(from: image)
            guard let raw,
                  !raw.isEmpty,
                  !raw.localizedCaseInsensitiveContains("smiley/"),
                  let url = HTMLTextExtractor.absoluteURL(from: raw) else {
                continue
            }
            imageURLs.append(url)
        }

        return ParsedMessage(text: text, imageURLs: imageURLs, chapterTitle: chapterTitle)
    }

    private static func readableText(from body: Element) throws -> String {
        var value = ""
        for child in body.getChildNodes() {
            try appendText(from: child, into: &value)
        }
        return normalizeText(value)
    }

    private static func appendText(from node: Node, into value: inout String) throws {
        if let textNode = node as? TextNode {
            value += textNode
                .getWholeText()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return
        }

        if let element = node as? Element {
            let tagName = element.tagName().lowercased()
            if tagName == "br" {
                value += "\n"
                return
            }
            if tagName == "li" {
                value += "• "
            }

            for child in element.getChildNodes() {
                try appendText(from: child, into: &value)
            }

            if blockBreakTags.contains(tagName) {
                value += "\n"
            }
            return
        }

        for child in node.getChildNodes() {
            try appendText(from: child, into: &value)
        }
    }

    private static func imageSource(from image: Element) throws -> String? {
        for attribute in ["zoomfile", "file", "src"] {
            let value = try image.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func normalizeText(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        value = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map {
                $0.replacingOccurrences(
                    of: #"[ \t]+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")

        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func urlComponents(from href: String) -> URLComponents? {
        guard let url = HTMLTextExtractor.absoluteURL(from: href) else {
            return URLComponents(string: href)
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: true)
    }

    private static func isSameThreadLink(components: URLComponents, href: String, threadID: String) -> Bool {
        if let tid = components.queryItems?.first(where: { $0.name == "tid" })?.value {
            return tid == threadID
        }
        return href.contains("thread-\(threadID)-")
    }

    private static func pageNumber(from components: URLComponents, href: String, threadID: String) -> Int? {
        if let page = components.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) {
            return page
        }

        return HTMLTextExtractor.firstMatch(
            pattern: #"thread-\#(threadID)-(\d+)-\d+\.html"#,
            in: href
        )?
        .dropFirst()
        .first
        .flatMap(Int.init)
    }

    private static let blockBreakTags: Set<String> = [
        "div",
        "p",
        "li",
        "tr",
        "dd",
        "blockquote"
    ]
}
