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
#endif
