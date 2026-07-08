import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct NovelReaderVerticalViewportMetrics: Equatable {
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

enum NovelReaderVerticalBoundaryDirection: Equatable {
    case previous
    case next
}

struct NovelReaderVerticalBoundaryPullState: Equatable {
    var direction: NovelReaderVerticalBoundaryDirection?
    var distance: CGFloat = 0
    var isArmed = false

    static let idle = NovelReaderVerticalBoundaryPullState()
}

struct NovelReaderVerticalSurfaceFrameValue: Equatable {
    let documentView: Int
    let frame: CGRect
}

struct NovelReaderVerticalPositioningFingerprint: Equatable {
    let generation: UInt64
    let view: Int
    let surfaceCount: Int
    let surfaceIndex: Int
    let intraSurfaceProgressBucket: Int
    let readingMode: ReaderReadingMode
}

struct NovelReaderSurfaceSelectionTag: Hashable {
    let view: Int
    let index: Int
}

let readerPadVisibleStatusBarTopInset: CGFloat = 32

struct NovelReaderVerticalSurfaceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: NovelReaderVerticalSurfaceFrameValue] { [:] }

    static func reduce(value: inout [Int: NovelReaderVerticalSurfaceFrameValue], nextValue: () -> [Int: NovelReaderVerticalSurfaceFrameValue]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct NovelReaderVerticalBoundaryPullBadge: View {
    let text: String
    let systemImage: String
    let progress: CGFloat
    let isArmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReaderGlassContainer(spacing: 8) {
            Label {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: systemImage)
                    .symbolVariant(isArmed ? .fill : .none)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .readerChromePanel(cornerRadius: 22, tint: badgeTint)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.22 + 0.38 * progress), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 4)
        }
    }

    private var badgeTint: Color {
        if isArmed {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
        return readerChromePanelTint(for: colorScheme)
    }
}

extension NovelChapterIdentity {
    /// Forum-page-keyed identities embed "#view:N#" (see
    /// `NovelReaderProjectionBuilder.chapterIdentity`); post-keyed identities
    /// carry no page number at all, so this returns nil for those and callers
    /// fall back to the reader's current view.
    var embeddedDocumentView: Int? {
        guard let match = rawValue.range(of: #"#view:(\d+)#"#, options: .regularExpression) else {
            return nil
        }
        let digits = rawValue[match].drop(while: { !$0.isNumber })
        return Int(digits)
    }
}

extension NovelTextSegmentIdentity {
    /// Segment identities are "<chapterIdentity>#text:N" / "...#image:N"
    /// (`NovelReaderProjectionBuilder.segmentSemantics`); this recovers the
    /// owning chapter identity by trimming that suffix.
    var chapterIdentity: NovelChapterIdentity? {
        guard let suffixRange = rawValue.range(of: #"#(text|image):\d+$"#, options: .regularExpression) else {
            return nil
        }
        return NovelChapterIdentity(rawValue: String(rawValue[..<suffixRange.lowerBound]))
    }
}

extension NovelReaderSurface {
    /// Best-effort external-block lookup for a long-pressed image URL. Only
    /// the surfaces passed in are searched, so a duplicate image URL reused
    /// across two different surfaces resolves to the first match.
    static func externalBlock(forImageURL url: URL, in surfaces: [NovelReaderSurface]) -> NovelReaderExternalBlock? {
        surfaces.lazy.flatMap(\.externalBlocks).first { $0.url == url }
    }
}

func novelImageLikeAnchor(forImageURL url: URL, in surfaces: [NovelReaderSurface]) -> NovelImageLikeAnchor? {
    guard let block = NovelReaderSurface.externalBlock(forImageURL: url, in: surfaces),
          let chapterIdentity = block.chapterIdentity,
          let imageSegmentIdentity = block.imageSegmentIdentity else {
        return nil
    }
    return NovelImageLikeAnchor(chapterIdentity: chapterIdentity, imageSegmentIdentity: imageSegmentIdentity.rawValue)
}
#endif
