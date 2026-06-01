import Foundation

public enum ReaderChapterTextComponents {
    public static func split(text: String, chapterTitle: String?) -> (title: String?, body: String?) {
        guard let chapterTitle else {
            return (nil, nil)
        }

        let trimmedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return (nil, nil)
        }

        if text == trimmedTitle {
            return (trimmedTitle, nil)
        }

        let lineBreakCandidates = ["\r\n", "\n", "\r"]
        for separator in lineBreakCandidates {
            let prefixedTitle = trimmedTitle + separator
            if text.hasPrefix(prefixedTitle) {
                let body = String(text.dropFirst(prefixedTitle.count))
                return (trimmedTitle, separator + body)
            }
        }

        return (nil, nil)
    }
}

struct ReaderParagraphIndentPlanner {
    static func indentedParagraphRangesAfterFirst(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        var isFirstParagraph = true

        while index < text.endIndex {
            let paragraphStart = index
            while index < text.endIndex, text[index].isReaderParagraphSeparator {
                index = text.index(after: index)
            }

            var paragraphEnd = index
            while paragraphEnd < text.endIndex, !text[paragraphEnd].isReaderParagraphSeparator {
                paragraphEnd = text.index(after: paragraphEnd)
            }

            let styleRange = paragraphStart ..< paragraphEnd
            if !isFirstParagraph, !styleRange.isEmpty {
                ranges.append(styleRange)
            }

            isFirstParagraph = false
            index = paragraphEnd
        }

        return ranges
    }
}

private extension Character {
    var isReaderParagraphSeparator: Bool {
        self == "\n" || self == "\r"
    }
}

#if canImport(UIKit)
import UIKit

public enum ReaderAttributedTextFactory {
    public static let defaultBaseFontSize: Double = 22

    public static func makeAttributedText(
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = defaultBaseFontSize,
        textColor: UIColor = .label,
        titleWeight: UIFont.Weight = .regular
    ) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let segments = ReaderChapterTextComponents.split(text: text, chapterTitle: chapterTitle)
        let pointSize = baseFontSize * settings.fontScale
        let firstBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: startsAtParagraphBoundary
        )
        let laterBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: true
        )
        let titleParagraphStyle = makeParagraphStyle(settings: settings, pointSize: pointSize, appliesFirstLineIndent: false)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.uiFont(size: pointSize, weight: .regular),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: firstBodyParagraphStyle,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.uiFont(size: pointSize, weight: titleWeight),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: titleParagraphStyle,
        ]

        if let title = segments.title {
            rendered.append(NSAttributedString(string: title, attributes: titleAttributes))
            if let body = segments.body {
                appendBody(
                    body,
                    to: rendered,
                    attributes: bodyAttributes,
                    laterParagraphStyle: laterBodyParagraphStyle,
                    startsAtParagraphBoundary: startsAtParagraphBoundary
                )
            }
        } else {
            appendBody(
                text,
                to: rendered,
                attributes: bodyAttributes,
                laterParagraphStyle: laterBodyParagraphStyle,
                startsAtParagraphBoundary: startsAtParagraphBoundary
            )
        }

        return rendered
    }

    public static func makeParagraphStyle(settings: ReaderAppearanceSettings) -> NSMutableParagraphStyle {
        makeParagraphStyle(settings: settings, pointSize: defaultBaseFontSize, appliesFirstLineIndent: true)
    }

    private static func makeParagraphStyle(
        settings: ReaderAppearanceSettings,
        pointSize: Double,
        appliesFirstLineIndent: Bool
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6 * settings.lineHeightScale
        style.alignment = settings.usesJustifiedText ? .justified : .natural
        style.lineBreakMode = .byWordWrapping
        if settings.indentsParagraphFirstLine, appliesFirstLineIndent {
            style.firstLineHeadIndent = CGFloat(pointSize * 2)
        }
        return style
    }

    private static func appendBody(
        _ body: String,
        to rendered: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        laterParagraphStyle: NSParagraphStyle,
        startsAtParagraphBoundary: Bool
    ) {
        let bodyStartLocation = rendered.length
        rendered.append(NSAttributedString(string: body, attributes: attributes))
        guard !startsAtParagraphBoundary else { return }

        for range in ReaderParagraphIndentPlanner.indentedParagraphRangesAfterFirst(in: body) {
            let location = body.distance(from: body.startIndex, to: range.lowerBound)
            let length = body.distance(from: range.lowerBound, to: range.upperBound)
            guard length > 0 else { continue }
            rendered.addAttribute(
                .paragraphStyle,
                value: laterParagraphStyle,
                range: NSRange(location: bodyStartLocation + location, length: length)
            )
        }
    }
}

public extension ReaderFontFamily {
    func uiFont(size: Double, weight: UIFont.Weight) -> UIFont {
        let pointSize = CGFloat(size)
        switch self {
        case .systemSans:
            return preferredFamilyFont(familyName: "PingFang SC", size: pointSize, weight: weight)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .systemSerif:
            return preferredFamilyFont(familyName: "Songti SC", size: pointSize, weight: weight)
                ?? systemFont(size: pointSize, weight: weight, design: .serif)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .rounded:
            return systemFont(size: pointSize, weight: weight, design: .rounded)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        }
    }

    func kerning(size: Double, scale: Double) -> CGFloat {
        CGFloat(size * scale * 0.55)
    }

    private func preferredFamilyFont(familyName: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        let descriptor = UIFontDescriptor(
            fontAttributes: [
                .family: familyName,
                .traits: [UIFontDescriptor.TraitKey.weight: weight],
            ]
        )
        let font = UIFont(descriptor: descriptor, size: size)
        return font.familyName == familyName ? font : nil
    }

    private func systemFont(size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont? {
        let baseDescriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        guard let designedDescriptor = baseDescriptor.withDesign(design) else {
            return nil
        }

        return UIFont(descriptor: designedDescriptor, size: size)
    }
}
#endif
