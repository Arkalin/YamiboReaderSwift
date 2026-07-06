import SwiftUI
import YamiboReaderCore

struct ForumThreadTextBlockView: View {
    let block: ForumThreadTextBlock
    let onURLTap: (URL) -> Void

    @ViewBuilder
    var body: some View {
        if block.rubies.isEmpty {
            plainText
        } else {
            ForumThreadRubyTextBlockView(
                segments: rubySegments,
                alignment: block.alignment,
                onURLTap: onURLTap
            )
        }
    }

    private var plainText: some View {
        Text(attributedText)
            .font(.body)
            .lineSpacing(4)
            .foregroundStyle(ForumColors.textDark)
            .multilineTextAlignment(block.alignment.swiftUITextAlignment)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: block.alignment.swiftUIFrameAlignment)
            .environment(\.openURL, OpenURLAction { url in
                onURLTap(url)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(block.text)
        let characters = Array(block.text)
        for run in block.styleRuns {
            guard run.start >= 0, run.start < characters.count else { continue }
            let end = min(characters.count, run.start + run.length)
            guard end > run.start else { continue }
            let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: run.start)
            let endIndex = attributed.index(attributed.startIndex, offsetByCharacters: end)
            attributed[startIndex ..< endIndex].font = forumThreadFont(for: run.style)
            if let foregroundColor = Color(forumThreadHex: run.style.foregroundHex) {
                attributed[startIndex ..< endIndex].foregroundColor = foregroundColor
            }
            if let backgroundColor = Color(forumThreadHex: run.style.backgroundHex) {
                attributed[startIndex ..< endIndex].backgroundColor = backgroundColor
            }
            if run.style.isUnderline {
                attributed[startIndex ..< endIndex].underlineStyle = .single
            }
            if run.style.isStrikethrough {
                attributed[startIndex ..< endIndex].strikethroughStyle = .single
            }
        }
        for link in block.links {
            guard link.start >= 0, link.start < characters.count else { continue }
            let end = min(characters.count, link.start + link.length)
            guard end > link.start else { continue }
            let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: link.start)
            let endIndex = attributed.index(attributed.startIndex, offsetByCharacters: end)
            attributed[startIndex ..< endIndex].link = link.url
            attributed[startIndex ..< endIndex].foregroundColor = ForumColors.brownPrimary
            attributed[startIndex ..< endIndex].underlineStyle = .single
        }
        return attributed
    }

    private var rubySegments: [ForumThreadRubySegment] {
        let textCount = Array(block.text).count
        let sortedRubies = block.rubies
            .filter { ruby in
                ruby.start >= 0
                    && ruby.length > 0
                    && ruby.start + ruby.length <= textCount
            }
            .sorted { first, second in
                first.start < second.start
            }
        var cursor = 0
        var segments: [ForumThreadRubySegment] = []

        for ruby in sortedRubies {
            guard ruby.start >= cursor else { continue }
            if cursor < ruby.start,
               let attributed = attributedTextSlice(start: cursor, length: ruby.start - cursor) {
                segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: nil))
            }
            if let attributed = attributedTextSlice(start: ruby.start, length: ruby.length) {
                segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: ruby.rubyText))
            }
            cursor = ruby.start + ruby.length
        }

        if cursor < textCount,
           let attributed = attributedTextSlice(start: cursor, length: textCount - cursor) {
            segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: nil))
        }

        return segments
    }

    private func attributedTextSlice(start: Int, length: Int) -> AttributedString? {
        guard length > 0 else { return nil }
        let attributed = attributedText
        let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: start)
        let endIndex = attributed.index(startIndex, offsetByCharacters: length)
        return AttributedString(attributed[startIndex ..< endIndex])
    }

    private func forumThreadFont(for style: ForumThreadTextStyle) -> Font {
        let baseSize = 17 * (style.relativeFontSize ?? 1)
        var font = Font.system(size: baseSize)
        if style.isBold {
            font = font.bold()
        }
        if style.isItalic {
            font = font.italic()
        }
        return font
    }
}

extension ForumThreadTextAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .center:
            return .center
        case .right:
            return .trailing
        case .start, .left:
            return .leading
        }
    }

    var swiftUIFrameAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .right:
            return .trailing
        case .start, .left:
            return .leading
        }
    }
}

private extension Color {
    init?(forumThreadHex hex: String?) {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = UInt64(normalized, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
