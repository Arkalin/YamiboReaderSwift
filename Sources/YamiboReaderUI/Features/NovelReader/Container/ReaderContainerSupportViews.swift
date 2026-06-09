import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderVerticalViewportMetrics: Equatable {
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

enum ReaderVerticalBoundaryDirection: Equatable {
    case previous
    case next
}

struct ReaderVerticalBoundaryPullState: Equatable {
    var direction: ReaderVerticalBoundaryDirection?
    var distance: CGFloat = 0
    var isArmed = false

    static let idle = ReaderVerticalBoundaryPullState()
}

struct ReaderVerticalSurfaceFrameValue: Equatable {
    let documentView: Int
    let frame: CGRect
}

struct ReaderImageBrowserItem: Identifiable, Equatable {
    let url: URL
    let title: String

    var id: String {
        url.absoluteString
    }
}

struct ReaderVerticalPositioningFingerprint: Equatable {
    let generation: UInt64
    let view: Int
    let surfaceCount: Int
    let surfaceIndex: Int
    let intraSurfaceProgressBucket: Int
    let readingMode: ReaderReadingMode
}

struct ReaderSurfaceSelectionTag: Hashable {
    let view: Int
    let index: Int
}

let readerPadVisibleStatusBarTopInset: CGFloat = 32

struct ReaderVerticalSurfaceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: ReaderVerticalSurfaceFrameValue] { [:] }

    static func reduce(value: inout [Int: ReaderVerticalSurfaceFrameValue], nextValue: () -> [Int: ReaderVerticalSurfaceFrameValue]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ReaderTopChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ReaderBottomChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ReaderVerticalBoundaryPullBadge: View {
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
