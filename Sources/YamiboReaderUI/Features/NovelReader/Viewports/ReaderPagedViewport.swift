import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

final class ReaderPagedViewportCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

struct ReaderPagedViewportContentIdentity: Equatable {
    var surfaces: [NovelReaderSurface]
    var settings: ReaderAppearanceSettings
    var refererURL: URL
    var sessionState: ReaderPagedViewportSessionIdentity
    var topInset: CGFloat
    var bottomInset: CGFloat

    init(
        surfaces: [NovelReaderSurface],
        settings: ReaderAppearanceSettings,
        refererURL: URL,
        sessionState: SessionState,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) {
        self.surfaces = surfaces
        self.settings = settings
        self.refererURL = refererURL
        self.sessionState = ReaderPagedViewportSessionIdentity(sessionState)
        self.topInset = topInset
        self.bottomInset = bottomInset
    }
}

struct ReaderPagedSpreadViewportContentIdentity: Equatable {
    var spreads: [NovelReaderPresentationSpread]
    var content: ReaderPagedViewportContentIdentity
}

struct ReaderPagedViewportSessionIdentity: Equatable {
    var userAgent: String
    var cookie: String

    init(_ sessionState: SessionState) {
        userAgent = sessionState.userAgent
        cookie = sessionState.cookie
    }
}
#endif
