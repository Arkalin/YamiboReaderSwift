import SwiftUI
import YamiboReaderCore

struct ReaderPagedPageTurnVisualMetrics: Equatable {
    var roundedPageIndex: Int
    var maskedPageIndex: Int
    var overlayAlpha: CGFloat
    var cornerRadius: CGFloat

    var isActive: Bool {
        overlayAlpha > 0
    }
}

enum ReaderPagedPageTurnPresentation {
    static let maxOverlayAlpha: CGFloat = 0.22
    static let fallbackPageCornerRadius: CGFloat = 56
    private static let completionThreshold: CGFloat = 0.001

    static func metrics(
        contentOffsetX: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int,
        restingPageIndex: Int,
        maxOverlayAlpha: CGFloat = Self.maxOverlayAlpha,
        cornerRadius: CGFloat = Self.fallbackPageCornerRadius
    ) -> ReaderPagedPageTurnVisualMetrics? {
        guard pageWidth > 0, pageCount > 1 else { return nil }

        let progress = contentOffsetX / pageWidth
        let clampedRestingIndex = min(max(restingPageIndex, 0), max(pageCount - 1, 0))
        let delta = progress - CGFloat(clampedRestingIndex)
        guard abs(delta) > completionThreshold else { return nil }

        let targetIndex = delta > 0 ? clampedRestingIndex + 1 : clampedRestingIndex - 1
        guard targetIndex >= 0, targetIndex < pageCount else { return nil }

        let turnProgress = min(max(abs(delta), 0), 1)
        guard turnProgress < 1 - completionThreshold else { return nil }

        return ReaderPagedPageTurnVisualMetrics(
            roundedPageIndex: clampedRestingIndex,
            maskedPageIndex: targetIndex,
            overlayAlpha: maxOverlayAlpha * (1 - turnProgress),
            cornerRadius: cornerRadius
        )
    }
}

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

enum ReaderPagedPageTurnBackground {
    static func dimmedPageColor(
        settings: ReaderAppearanceSettings,
        traitCollection: UITraitCollection,
        overlayAlpha: CGFloat
    ) -> UIColor {
        let base = pageColor(
            for: settings.backgroundStyle,
            isDarkMode: traitCollection.userInterfaceStyle == .dark
        )
        return blend(base: base, overlay: .black, alpha: min(max(overlayAlpha, 0), 1))
    }

    private static func pageColor(for style: ReaderBackgroundStyle, isDarkMode: Bool) -> UIColor {
        if isDarkMode {
            switch style {
            case .system:
                return UIColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1)
            case .paper:
                return UIColor(red: 0.21, green: 0.19, blue: 0.16, alpha: 1)
            case .mint:
                return UIColor(red: 0.14, green: 0.18, blue: 0.16, alpha: 1)
            case .sakura:
                return UIColor(red: 0.19, green: 0.16, blue: 0.18, alpha: 1)
            }
        }

        switch style {
        case .system:
            return UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
        case .paper:
            return UIColor(red: 0.945, green: 0.882, blue: 0.769, alpha: 1)
        case .mint:
            return UIColor(red: 0.92, green: 0.97, blue: 0.93, alpha: 1)
        case .sakura:
            return UIColor(red: 0.97, green: 0.92, blue: 0.93, alpha: 1)
        }
    }

    private static func blend(base: UIColor, overlay: UIColor, alpha: CGFloat) -> UIColor {
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var overlayRed: CGFloat = 0
        var overlayGreen: CGFloat = 0
        var overlayBlue: CGFloat = 0
        var overlayAlpha: CGFloat = 0

        base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
        overlay.getRed(&overlayRed, green: &overlayGreen, blue: &overlayBlue, alpha: &overlayAlpha)

        return UIColor(
            red: baseRed * (1 - alpha) + overlayRed * alpha,
            green: baseGreen * (1 - alpha) + overlayGreen * alpha,
            blue: baseBlue * (1 - alpha) + overlayBlue * alpha,
            alpha: baseAlpha
        )
    }
}

enum ReaderPagedPageTurnCornerRadius {
    static let fallbackRadius = ReaderPagedPageTurnPresentation.fallbackPageCornerRadius
    private static let displayCornerRadiusSelectorName = ["_display", "Corner", "Radius"].joined()

    static func radius(for screen: UIScreen?) -> CGFloat {
        guard let screen else { return fallbackRadius }
        let selector = NSSelectorFromString(displayCornerRadiusSelectorName)
        guard screen.responds(to: selector),
              let value = screen.value(forKey: displayCornerRadiusSelectorName) as? NSNumber else {
            return fallbackRadius
        }
        let radius = CGFloat(truncating: value)
        return radius > 0 ? radius : fallbackRadius
    }
}

final class ReaderPagedViewportCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

final class ReaderPagedPageTurnCell: UICollectionViewCell {
    private let pageTurnOverlayView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configurePageTurnOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePageTurnOverlay()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetPageTurnVisuals()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensurePageTurnOverlay()
        pageTurnOverlayView.frame = bounds
        bringSubviewToFront(pageTurnOverlayView)
    }

    func applyPageTurnVisuals(overlayAlpha: CGFloat, cornerRadius: CGFloat) {
        ensurePageTurnOverlay()
        pageTurnOverlayView.alpha = min(max(overlayAlpha, 0), 1)
        layer.cornerRadius = max(cornerRadius, 0)
        layer.cornerCurve = .continuous
        layer.masksToBounds = cornerRadius > 0
        bringSubviewToFront(pageTurnOverlayView)
    }

    func resetPageTurnVisuals() {
        ensurePageTurnOverlay()
        pageTurnOverlayView.alpha = 0
        layer.cornerRadius = 0
        layer.masksToBounds = false
    }

    private func configurePageTurnOverlay() {
        pageTurnOverlayView.backgroundColor = .black
        pageTurnOverlayView.alpha = 0
        pageTurnOverlayView.isUserInteractionEnabled = false
        pageTurnOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ensurePageTurnOverlay()
    }

    private func ensurePageTurnOverlay() {
        guard pageTurnOverlayView.superview !== self else { return }
        pageTurnOverlayView.removeFromSuperview()
        addSubview(pageTurnOverlayView)
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

struct ReaderPagedScrollAnimationRequest: Equatable {
    let id: UUID
    let pagerIdentity: ReaderPagedPagerIdentity
    let selectionIndex: Int

    init(
        id: UUID = UUID(),
        pagerIdentity: ReaderPagedPagerIdentity,
        selectionIndex: Int
    ) {
        self.id = id
        self.pagerIdentity = pagerIdentity
        self.selectionIndex = max(0, selectionIndex)
    }
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
