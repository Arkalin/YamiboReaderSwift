import CoreGraphics
import YamiboReaderCore

enum MangaPagedLayoutPolicy {
    static func usesTwoPageSpread(
        settings: MangaReaderSettings,
        isPadDevice: Bool,
        availableSize: CGSize
    ) -> Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            isPadDevice &&
            availableSize.width > availableSize.height
    }

    static func effectivePageScaleMode(
        settings: MangaReaderSettings,
        usesTwoPageSpread: Bool
    ) -> MangaPageScaleMode {
        usesTwoPageSpread ? .fitWidth : settings.pageScaleMode
    }
}
