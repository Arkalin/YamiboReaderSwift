import Foundation
import SwiftSoup

enum ReaderHTMLDOMParser {
    struct Context {
        let document: Document
    }

    struct ParsedMessage {
        let segments: [ReaderSegment]
        let segmentInlineStyles: [[ReaderInlineTextStyleRange]]
        let chapterTitle: String?
        let ownerPostID: String?
    }

    private struct ParsedSegment {
        let segment: ReaderSegment
        let inlineTextStyles: [ReaderInlineTextStyleRange]
    }

    private struct StyledCharacter {
        let character: Character
        let isBold: Bool
    }

    static func parse(html: String) throws -> Context {
        Context(document: try SwiftSoup.parse(html))
    }

    static func messageNodes(in context: Context) throws -> [Element] {
        let nodes = try context.document.select(".message, [id^=postmessage_]")
        var uniqueNodes: [Element] = []
        for node in nodes {
            if !isPostMessageElement(node),
               ((try? node.select("[id^=postmessage_]").isEmpty()) == false) {
                continue
            }
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
            return ParsedMessage(segments: [], segmentInlineStyles: [], chapterTitle: nil, ownerPostID: postID(from: element))
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

        var parsedSegments = try orderedSegments(from: body, chapterTitle: chapterTitle)
        parsedSegments.append(contentsOf: try siblingAttachmentImageSegments(after: element, chapterTitle: chapterTitle))
        return ParsedMessage(
            segments: parsedSegments.map(\.segment),
            segmentInlineStyles: parsedSegments.map(\.inlineTextStyles),
            chapterTitle: chapterTitle,
            ownerPostID: postID(from: element)
        )
    }

    private static func siblingAttachmentImageSegments(after element: Element, chapterTitle: String?) throws -> [ParsedSegment] {
        guard element.hasClass("message") else { return [] }

        var segments: [ParsedSegment] = []
        var sibling = try element.nextElementSibling()
        while let candidate = sibling, isAttachmentImageList(candidate) {
            for image in try candidate.select("img") {
                guard let url = try imageURL(from: image) else { continue }
                segments.append(
                    ParsedSegment(
                        segment: .image(url, chapterTitle: chapterTitle),
                        inlineTextStyles: []
                    )
                )
            }
            sibling = try candidate.nextElementSibling()
        }
        return segments
    }

    private static func isAttachmentImageList(_ element: Element) -> Bool {
        element.tagName().lowercased() == "ul" && element.hasClass("img_one")
    }

    private static func postID(from element: Element) -> String? {
        let rawID = (try? element.attr("id"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let postID = postID(fromRawID: rawID, prefix: "postmessage_") {
            return postID
        }
        if let postID = postID(fromRawID: rawID, prefix: "pid") {
            return postID
        }

        var current = element.parent()
        while let candidate = current {
            let candidateID = (try? candidate.attr("id"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let postID = postID(fromRawID: candidateID, prefix: "post_") {
                return postID
            }
            if let postID = postID(fromRawID: candidateID, prefix: "pid") {
                return postID
            }
            current = candidate.parent()
        }
        return nil
    }

    private static func isPostMessageElement(_ element: Element) -> Bool {
        let rawID = (try? element.attr("id"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rawID.hasPrefix("postmessage_")
    }

    private static func postID(fromRawID rawID: String, prefix: String) -> String? {
        guard rawID.hasPrefix(prefix) else { return nil }
        let postID = String(rawID.dropFirst(prefix.count))
        guard !postID.isEmpty, postID.allSatisfy(\.isNumber) else { return nil }
        return postID
    }

    private static func readableText(from body: Element) throws -> String {
        var value = ""
        for child in body.getChildNodes() {
            try appendText(from: child, into: &value)
        }
        return normalizeText(value)
    }

    private static func orderedSegments(from body: Element, chapterTitle: String?) throws -> [ParsedSegment] {
        var segments: [ParsedSegment] = []
        var text: [StyledCharacter] = []

        func flushText() {
            let normalized = normalizeStyledText(text)
            guard !normalized.text.isEmpty else {
                text = []
                return
            }
            segments.append(
                ParsedSegment(
                    segment: .text(normalized.text, chapterTitle: chapterTitle),
                    inlineTextStyles: normalized.inlineTextStyles
                )
            )
            text = []
        }

        func appendText(_ value: String, isBold: Bool) {
            for character in value {
                text.append(StyledCharacter(character: character, isBold: isBold))
            }
        }

        func appendSegments(from node: Node, isBold: Bool) throws {
            if let textNode = node as? TextNode {
                appendText(
                    textNode
                    .getWholeText()
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression),
                    isBold: isBold
                )
                return
            }

            if let element = node as? Element {
                let tagName = element.tagName().lowercased()
                let nextBold = resolvedBoldState(for: element, tagName: tagName, inheritedBold: isBold)
                if tagName == "br" {
                    appendText("\n", isBold: nextBold)
                    return
                }
                if tagName == "img" {
                    guard let url = try imageURL(from: element) else { return }
                    flushText()
                    segments.append(ParsedSegment(segment: .image(url, chapterTitle: chapterTitle), inlineTextStyles: []))
                    return
                }
                if tagName == "li" {
                    appendText("• ", isBold: nextBold)
                }

                for child in element.getChildNodes() {
                    try appendSegments(from: child, isBold: nextBold)
                }

                if blockBreakTags.contains(tagName) {
                    appendText("\n", isBold: nextBold)
                }
                return
            }

            for child in node.getChildNodes() {
                try appendSegments(from: child, isBold: isBold)
            }
        }

        for child in body.getChildNodes() {
            try appendSegments(from: child, isBold: false)
        }
        flushText()

        return segments
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

    private static func resolvedBoldState(
        for element: Element,
        tagName: String,
        inheritedBold: Bool
    ) -> Bool {
        var isBold = inheritedBold
        if tagName == "b" || tagName == "strong" {
            isBold = true
        }
        if let styleBold = inlineFontWeightBoldState(for: element) {
            isBold = styleBold
        }
        return isBold
    }

    private static func inlineFontWeightBoldState(for element: Element) -> Bool? {
        let style = (try? element.attr("style"))?.lowercased() ?? ""
        guard !style.isEmpty else { return nil }

        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, parts[0] == "font-weight" else { continue }
            let value = parts[1]
                .replacingOccurrences(of: "!important", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "bold" || value == "bolder" {
                return true
            }
            if value == "normal" || value == "lighter" {
                return false
            }
            let numericPrefix = value.prefix { $0.isNumber }
            if let weight = Int(numericPrefix) {
                return weight >= 600
            }
        }
        return nil
    }

    private static func normalizeStyledText(
        _ text: [StyledCharacter]
    ) -> (text: String, inlineTextStyles: [ReaderInlineTextStyleRange]) {
        let normalizedLineBreaks = normalizeStyledLineBreaks(text)
        var lines: [[StyledCharacter]] = [[]]
        for character in normalizedLineBreaks {
            if character.character == "\n" {
                lines.append([])
            } else {
                lines[lines.count - 1].append(character)
            }
        }

        var normalized: [StyledCharacter] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                normalized.append(StyledCharacter(character: "\n", isBold: false))
            }
            normalized.append(contentsOf: normalizeStyledLine(line))
        }

        normalized = collapseExcessNewlines(in: normalized)
        normalized = trimStyledWhitespaceAndNewlines(normalized)

        var output = ""
        var inlineTextStyles: [ReaderInlineTextStyleRange] = []
        var boldStart: Int?
        for character in normalized {
            let location = output.count
            if character.isBold {
                if boldStart == nil {
                    boldStart = location
                }
            } else if let start = boldStart {
                if location > start {
                    inlineTextStyles.append(
                        ReaderInlineTextStyleRange(
                            style: .bold,
                            range: ReaderCharacterRange(location: start, length: location - start)
                        )
                    )
                }
                boldStart = nil
            }
            output.append(character.character)
        }
        if let start = boldStart, output.count > start {
            inlineTextStyles.append(
                ReaderInlineTextStyleRange(
                    style: .bold,
                    range: ReaderCharacterRange(location: start, length: output.count - start)
                )
            )
        }
        return (output, inlineTextStyles)
    }

    private static func normalizeStyledLineBreaks(_ text: [StyledCharacter]) -> [StyledCharacter] {
        var result: [StyledCharacter] = []
        var index = 0
        while index < text.count {
            let character = text[index]
            if character.character == "\r" {
                result.append(StyledCharacter(character: "\n", isBold: character.isBold))
                if index + 1 < text.count, text[index + 1].character == "\n" {
                    index += 1
                }
            } else if character.character == "\u{00A0}" {
                result.append(StyledCharacter(character: " ", isBold: character.isBold))
            } else {
                result.append(character)
            }
            index += 1
        }
        return result
    }

    private static func normalizeStyledLine(_ line: [StyledCharacter]) -> [StyledCharacter] {
        var result: [StyledCharacter] = []
        var pendingWhitespaceIsBold = false
        var hasPendingWhitespace = false

        for character in line {
            if character.character == " " || character.character == "\t" {
                hasPendingWhitespace = true
                pendingWhitespaceIsBold = pendingWhitespaceIsBold || character.isBold
                continue
            }
            if hasPendingWhitespace, !result.isEmpty {
                result.append(StyledCharacter(character: " ", isBold: pendingWhitespaceIsBold))
            }
            hasPendingWhitespace = false
            pendingWhitespaceIsBold = false
            result.append(character)
        }

        return result
    }

    private static func collapseExcessNewlines(in text: [StyledCharacter]) -> [StyledCharacter] {
        var result: [StyledCharacter] = []
        var newlineCount = 0
        for character in text {
            if character.character == "\n" {
                newlineCount += 1
                if newlineCount <= 2 {
                    result.append(StyledCharacter(character: "\n", isBold: false))
                }
            } else {
                newlineCount = 0
                result.append(character)
            }
        }
        return result
    }

    private static func trimStyledWhitespaceAndNewlines(_ text: [StyledCharacter]) -> [StyledCharacter] {
        var start = text.startIndex
        var end = text.endIndex
        while start < end, isTrimmable(text[start].character) {
            start += 1
        }
        while end > start, isTrimmable(text[text.index(before: end)].character) {
            end -= 1
        }
        return Array(text[start..<end])
    }

    private static func isTrimmable(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\n" || character == "\r"
    }

    private static func imageURL(from image: Element) throws -> URL? {
        let raw = try imageSource(from: image)
        guard let raw,
              !raw.isEmpty,
              !raw.localizedCaseInsensitiveContains("smiley/") else {
            return nil
        }
        return HTMLTextExtractor.absoluteURL(from: raw)
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
