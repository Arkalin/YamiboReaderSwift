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

#if canImport(UIKit)
import UIKit

public enum ReaderAttributedTextFactory {
    public static let defaultBaseFontSize: Double = 22

    public static func makeAttributedText(
        text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = defaultBaseFontSize,
        textColor: UIColor = .label,
        titleWeight: UIFont.Weight = .regular
    ) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let segments = ReaderChapterTextComponents.split(text: text, chapterTitle: chapterTitle)
        let paragraphStyle = makeParagraphStyle(settings: settings)
        let pointSize = baseFontSize * settings.fontScale
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.uiFont(size: pointSize, weight: .regular),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.uiFont(size: pointSize, weight: titleWeight),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        if let title = segments.title {
            rendered.append(NSAttributedString(string: title, attributes: titleAttributes))
            if let body = segments.body {
                rendered.append(NSAttributedString(string: body, attributes: bodyAttributes))
            }
        } else {
            rendered.append(NSAttributedString(string: text, attributes: bodyAttributes))
        }

        return rendered
    }

    public static func makeParagraphStyle(settings: ReaderAppearanceSettings) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6 * settings.lineHeightScale
        style.alignment = settings.usesJustifiedText ? .justified : .natural
        style.lineBreakMode = .byWordWrapping
        return style
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
