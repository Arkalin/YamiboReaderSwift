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

enum MangaPagedViewportResizePolicy {
    static func alignedContentOffsetX(
        previousContentOffsetX: CGFloat,
        previousViewportSize: CGSize?,
        currentViewportSize: CGSize,
        itemCount: Int
    ) -> CGFloat? {
        guard let previousViewportSize,
              previousViewportSize != currentViewportSize,
              previousViewportSize.width > 0,
              previousViewportSize.height > 0,
              currentViewportSize.width > 0,
              currentViewportSize.height > 0,
              itemCount > 0 else {
            return nil
        }

        let itemIndex = Int((previousContentOffsetX / previousViewportSize.width).rounded())
        let clampedItemIndex = min(max(itemIndex, 0), itemCount - 1)
        return CGFloat(clampedItemIndex) * currentViewportSize.width
    }
}
