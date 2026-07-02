import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderPagedPageSurfaceContainer<Content: View>: View {
    let settings: ReaderAppearanceSettings
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(readerThemeColor(for: settings.backgroundStyle, colorScheme: colorScheme))
    }
}

struct ReaderPagedViewportContentIdentity: Equatable {
    var surfaces: [NovelReaderSurface]
    var settings: ReaderAppearanceSettings
    var refererURL: URL
    var topInset: CGFloat
    var bottomInset: CGFloat

    init(
        surfaces: [NovelReaderSurface],
        settings: ReaderAppearanceSettings,
        refererURL: URL,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) {
        self.surfaces = surfaces
        self.settings = settings
        self.refererURL = refererURL
        self.topInset = topInset
        self.bottomInset = bottomInset
    }
}

struct ReaderPagedSpreadViewportContentIdentity: Equatable {
    var spreads: [NovelReaderPresentationSpread]
    var content: ReaderPagedViewportContentIdentity
}

#endif
