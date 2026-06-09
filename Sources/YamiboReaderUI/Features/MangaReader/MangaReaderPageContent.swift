import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaPageContent: View {
    let page: MangaPage
    let refererURL: URL
    let imageRepository: MangaImageRepository
    let zoomEnabled: Bool
    @Binding var activeZoomPageID: MangaPage.ID?
    @Binding var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    let usesOverlayPresentation: Bool
    let readerCoordinateSpaceName: String?
    let showsChapterTitle: Bool
    let onToggleChrome: (() -> Void)?

    var body: some View {
        let content = VStack(spacing: 10) {
            MangaAuthenticatedImage(
                pageID: page.id,
                url: page.imageURL,
                refererURL: refererURL,
                imageRepository: imageRepository,
                zoomEnabled: zoomEnabled,
                activeZoomPageID: $activeZoomPageID,
                verticalZoomOverlay: $verticalZoomOverlay,
                usesOverlayPresentation: usesOverlayPresentation,
                readerCoordinateSpaceName: readerCoordinateSpaceName
            )
            if showsChapterTitle {
                Text(page.chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let onToggleChrome {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleChrome()
                }
        } else {
            content
        }
    }
}

@MainActor
private final class MangaImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private let url: URL
    private let refererURL: URL
    private let imageRepository: MangaImageRepository
    private var didStart = false

    init(url: URL, refererURL: URL, imageRepository: MangaImageRepository) {
        self.url = url
        self.refererURL = refererURL
        self.imageRepository = imageRepository
    }

    func loadIfNeeded() async {
        guard !didStart, image == nil else { return }
        didStart = true

        do {
            let data = try await imageRepository.imageData(
                for: MangaImageRequest(
                    imageURL: url,
                    refererURL: refererURL
                )
            )
            guard let image = UIImage(data: data) else {
                didFail = true
                return
            }
            self.image = image
        } catch {
            didFail = true
        }
    }
}

private struct MangaAuthenticatedImage: View {
    private static let defaultPlaceholderAspectRatio: CGFloat = 0.72

    @StateObject private var loader: MangaImageLoader
    let imageURL: URL
    let pageID: MangaPage.ID
    let zoomEnabled: Bool
    @Binding var activeZoomPageID: MangaPage.ID?
    @Binding var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    let usesOverlayPresentation: Bool
    let readerCoordinateSpaceName: String?
    @State private var estimatedAspectRatio: CGFloat = Self.defaultPlaceholderAspectRatio
    @State private var baseImageSize: CGSize = .zero
    @State private var imageFrameInReader: CGRect = .zero
    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    init(
        pageID: MangaPage.ID,
        url: URL,
        refererURL: URL,
        imageRepository: MangaImageRepository,
        zoomEnabled: Bool,
        activeZoomPageID: Binding<MangaPage.ID?>,
        verticalZoomOverlay: Binding<MangaVerticalZoomOverlayState?>,
        usesOverlayPresentation: Bool,
        readerCoordinateSpaceName: String?
    ) {
        self.imageURL = url
        self.pageID = pageID
        _loader = StateObject(
            wrappedValue: MangaImageLoader(
                url: url,
                refererURL: refererURL,
                imageRepository: imageRepository
            )
        )
        self.zoomEnabled = zoomEnabled
        _activeZoomPageID = activeZoomPageID
        _verticalZoomOverlay = verticalZoomOverlay
        self.usesOverlayPresentation = usesOverlayPresentation
        self.readerCoordinateSpaceName = readerCoordinateSpaceName
    }

    var body: some View {
        optionalDragGesture(
            Group {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: MangaImageBaseSizePreferenceKey.self, value: geometry.size)
                            }
                        )
                        .background(frameMeasurementOverlay)
                        .scaleEffect(inlineEffectiveScale)
                        .offset(
                            x: inlineOffset.width,
                            y: inlineOffset.height
                        )
                        .opacity(shouldHideInlineImage ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: inlineSteadyScale)
                        .animation(.easeOut(duration: 0.2), value: inlineSteadyOffset)
                } else if loader.didFail {
                    Label(L10n.string("image.load_failed"), systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                } else {
                    placeholderView
                }
            }
        )
        .frame(maxWidth: .infinity)
        .task {
            estimatedAspectRatio = MangaImageAspectRatioCache.aspectRatio(for: imageURL)
                ?? Self.defaultPlaceholderAspectRatio
            await loader.loadIfNeeded()
        }
        .onChange(of: pageID) { _, _ in
            resetInteractionState()
            estimatedAspectRatio = MangaImageAspectRatioCache.aspectRatio(for: imageURL)
                ?? Self.defaultPlaceholderAspectRatio
        }
        .onChange(of: loader.image) { _, newImage in
            guard let newImage else { return }
            let size = newImage.size
            guard size.width > 0, size.height > 0 else { return }
            let aspectRatio = size.width / size.height
            estimatedAspectRatio = aspectRatio
            MangaImageAspectRatioCache.store(aspectRatio: aspectRatio, for: imageURL)
        }
        .onChange(of: zoomEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            resetInteractionState()
        }
        .onChange(of: activeZoomPageID) { _, newValue in
            guard let newValue, newValue != pageID else {
                if newValue == nil, usesOverlayPresentation {
                    verticalZoomOverlay = nil
                }
                return
            }
            guard steadyScale > 1.01 || (verticalZoomOverlay?.pageID == pageID) else { return }
            resetInteractionState()
        }
        .onPreferenceChange(MangaImageBaseSizePreferenceKey.self) { newValue in
            updateBaseImageSize(newValue)
        }
        .simultaneousGesture(doubleTapGesture)
        .simultaneousGesture(magnifyGesture)
    }

    private var placeholderView: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let aspectRatio = max(0.2, estimatedAspectRatio)
            let height = max(240, width / aspectRatio)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white.opacity(0.85))
                    Text(L10n.string("image.loading"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(width: width, height: height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: placeholderHeight)
    }

    private var placeholderHeight: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let aspectRatio = max(0.2, estimatedAspectRatio)
        return max(240, screenWidth / aspectRatio)
    }

    private var effectiveScale: CGFloat {
        steadyScale * gestureScale
    }

    private var inlineEffectiveScale: CGFloat {
        usesOverlayPresentation ? 1 : effectiveScale
    }

    private var inlineSteadyScale: CGFloat {
        usesOverlayPresentation ? 1 : steadyScale
    }

    private var inlineOffset: CGSize {
        usesOverlayPresentation ? .zero : CGSize(
            width: steadyOffset.width + gestureOffset.width,
            height: steadyOffset.height + gestureOffset.height
        )
    }

    private var inlineSteadyOffset: CGSize {
        usesOverlayPresentation ? .zero : steadyOffset
    }

    private var shouldHideInlineImage: Bool {
        usesOverlayPresentation && verticalZoomOverlay?.pageID == pageID
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard zoomEnabled else { return }
                if usesOverlayPresentation {
                    if verticalZoomOverlay?.pageID == pageID {
                        resetInteractionState()
                    } else {
                        guard canBeginZoom else { return }
                        activateVerticalOverlay(targetScale: 2)
                    }
                } else {
                    if steadyScale > 1.05 {
                        resetInteractionState()
                    } else {
                        guard canBeginZoom else { return }
                        steadyScale = 2
                        steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
                        gestureOffset = .zero
                        activeZoomPageID = pageID
                    }
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard canContinueMagnify else {
                    gestureScale = 1
                    return
                }
                if usesOverlayPresentation {
                    activateVerticalOverlayIfNeeded()
                    guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
                    overlay.gestureScale = value.magnification
                    verticalZoomOverlay = overlay
                } else {
                    gestureScale = value.magnification
                }
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard canContinueMagnify else {
                    gestureScale = 1
                    return
                }
                if usesOverlayPresentation {
                    activateVerticalOverlayIfNeeded()
                    guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
                    overlay.steadyScale = min(4, max(1, overlay.steadyScale * value.magnification))
                    overlay.gestureScale = 1
                    if overlay.steadyScale <= 1.01 {
                        resetInteractionState()
                    } else {
                        overlay.steadyOffset = clampedOffset(overlay.steadyOffset, scale: overlay.steadyScale)
                        overlay.gestureOffset = .zero
                        verticalZoomOverlay = overlay
                        activeZoomPageID = pageID
                    }
                } else {
                    steadyScale = min(4, max(1, steadyScale * value.magnification))
                    gestureScale = 1
                    if steadyScale <= 1.01 {
                        resetInteractionState()
                    } else {
                        steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
                        gestureOffset = .zero
                        activeZoomPageID = pageID
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                gestureOffset = clampedGestureTranslation(value.translation)
            }
            .onEnded { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                steadyOffset = clampedOffset(
                    CGSize(
                        width: steadyOffset.width + value.translation.width,
                        height: steadyOffset.height + value.translation.height
                    ),
                    scale: steadyScale
                )
                gestureOffset = .zero
                if steadyScale <= 1.05 {
                    steadyOffset = .zero
                }
            }
    }

    @ViewBuilder
    private func optionalDragGesture<Content: View>(_ content: Content) -> some View {
        if effectiveScale > 1.01 {
            content.simultaneousGesture(dragGesture)
        } else {
            content
        }
    }

    private func resetInteractionState() {
        baseImageSize = .zero
        imageFrameInReader = .zero
        steadyScale = 1
        gestureScale = 1
        steadyOffset = .zero
        gestureOffset = .zero
        if verticalZoomOverlay?.pageID == pageID {
            verticalZoomOverlay = nil
        }
        if activeZoomPageID == pageID {
            activeZoomPageID = nil
        }
    }

    private func clampedGestureTranslation(_ translation: CGSize) -> CGSize {
        let proposed = CGSize(
            width: steadyOffset.width + translation.width,
            height: steadyOffset.height + translation.height
        )
        let clamped = clampedOffset(proposed, scale: steadyScale)
        return CGSize(
            width: clamped.width - steadyOffset.width,
            height: clamped.height - steadyOffset.height
        )
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let bounds = dragBounds(for: scale)
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposed.width)),
            height: min(bounds.height, max(-bounds.height, proposed.height))
        )
    }

    private func dragBounds(for scale: CGFloat) -> CGSize {
        guard baseImageSize.width > 0, baseImageSize.height > 0 else {
            return .zero
        }

        return CGSize(
            width: max(0, (baseImageSize.width * scale - baseImageSize.width) / 2),
            height: max(0, (baseImageSize.height * scale - baseImageSize.height) / 2)
        )
    }

    private var canBeginZoom: Bool {
        activeZoomPageID == nil || activeZoomPageID == pageID
    }

    private var canContinueMagnify: Bool {
        if usesOverlayPresentation {
            return (verticalZoomOverlay?.pageID == pageID) || canBeginZoom
        }
        return steadyScale > 1.01 || canBeginZoom
    }

    @ViewBuilder
    private var frameMeasurementOverlay: some View {
        if let readerCoordinateSpaceName {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateImageFrameInReader(geometry.frame(in: .named(readerCoordinateSpaceName)))
                    }
                    .onChange(of: geometry.frame(in: .named(readerCoordinateSpaceName))) { _, newValue in
                        updateImageFrameInReader(newValue)
                    }
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func updateBaseImageSize(_ newValue: CGSize) {
        guard baseImageSize.isMeaningfullyDifferent(from: newValue) else { return }
        baseImageSize = newValue
        if usesOverlayPresentation {
            updateVerticalOverlayIfNeeded()
        } else {
            steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
            gestureOffset = .zero
        }
    }

    private func updateImageFrameInReader(_ newValue: CGRect) {
        guard imageFrameInReader.isMeaningfullyDifferent(from: newValue) else { return }
        imageFrameInReader = newValue
        updateVerticalOverlayIfNeeded()
    }

    private func activateVerticalOverlay(targetScale: CGFloat) {
        guard let image = loader.image else { return }
        guard baseImageSize != .zero, imageFrameInReader != .zero else { return }
        activeZoomPageID = pageID
        verticalZoomOverlay = MangaVerticalZoomOverlayState(
            pageID: pageID,
            image: image,
            frame: imageFrameInReader,
            baseImageSize: baseImageSize,
            steadyScale: targetScale,
            gestureScale: 1,
            steadyOffset: .zero,
            gestureOffset: .zero
        )
    }

    private func activateVerticalOverlayIfNeeded() {
        guard usesOverlayPresentation else { return }
        if verticalZoomOverlay?.pageID != pageID {
            activateVerticalOverlay(targetScale: 1)
        }
    }

    private func updateVerticalOverlayIfNeeded() {
        guard usesOverlayPresentation else { return }
        guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
        overlay.frame = imageFrameInReader
        overlay.baseImageSize = baseImageSize
        overlay.steadyOffset = clampedOffset(overlay.steadyOffset, scale: overlay.steadyScale)
        overlay.gestureOffset = .zero
        if let image = loader.image {
            overlay.image = image
        }
        verticalZoomOverlay = overlay
    }
}

@MainActor
private enum MangaImageAspectRatioCache {
    private static let cache = NSCache<NSURL, NSNumber>()

    static func aspectRatio(for url: URL) -> CGFloat? {
        cache.object(forKey: url as NSURL).map { CGFloat(truncating: $0) }
    }

    static func store(aspectRatio: CGFloat, for url: URL) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        cache.setObject(NSNumber(value: Double(aspectRatio)), forKey: url as NSURL)
    }
}

private struct MangaImageBaseSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private extension CGSize {
    func isMeaningfullyDifferent(from other: CGSize, threshold: CGFloat = 0.5) -> Bool {
        abs(width - other.width) > threshold || abs(height - other.height) > threshold
    }
}

private extension CGRect {
    func isMeaningfullyDifferent(from other: CGRect, threshold: CGFloat = 0.5) -> Bool {
        abs(origin.x - other.origin.x) > threshold
            || abs(origin.y - other.origin.y) > threshold
            || size.isMeaningfullyDifferent(from: other.size, threshold: threshold)
    }
}

struct MangaVerticalZoomOverlayState {
    let pageID: MangaPage.ID
    var image: UIImage
    var frame: CGRect
    var baseImageSize: CGSize
    var steadyScale: CGFloat
    var gestureScale: CGFloat
    var steadyOffset: CGSize
    var gestureOffset: CGSize
}

struct MangaVerticalZoomOverlay: View {
    @Binding var overlay: MangaVerticalZoomOverlayState?
    @Binding var activeZoomPageID: MangaPage.ID?
    let zoomEnabled: Bool

    var body: some View {
        if let overlay {
            Image(uiImage: overlay.image)
                .resizable()
                .scaledToFit()
                .frame(width: overlay.baseImageSize.width, height: overlay.baseImageSize.height)
                .scaleEffect(overlay.steadyScale * overlay.gestureScale)
                .offset(
                    x: overlay.steadyOffset.width + overlay.gestureOffset.width,
                    y: overlay.steadyOffset.height + overlay.gestureOffset.height
                )
                .position(x: overlay.frame.midX, y: overlay.frame.midY)
                .animation(.easeOut(duration: 0.2), value: overlay.steadyScale)
                .animation(.easeOut(duration: 0.2), value: overlay.steadyOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(doubleTapGesture)
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard zoomEnabled else { return }
                reset()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                overlay.gestureScale = value.magnification
                self.overlay = overlay
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                overlay.steadyScale = min(4, max(1, overlay.steadyScale * value.magnification))
                overlay.gestureScale = 1
                if overlay.steadyScale <= 1.01 {
                    reset()
                } else {
                    overlay.steadyOffset = clampedOffset(overlay.steadyOffset, for: overlay)
                    overlay.gestureOffset = .zero
                    self.overlay = overlay
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                guard overlay.steadyScale > 1 else { return }
                overlay.gestureOffset = clampedGestureTranslation(value.translation, for: overlay)
                self.overlay = overlay
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                guard overlay.steadyScale > 1 else { return }
                overlay.steadyOffset = clampedOffset(
                    CGSize(
                        width: overlay.steadyOffset.width + value.translation.width,
                        height: overlay.steadyOffset.height + value.translation.height
                    ),
                    for: overlay
                )
                overlay.gestureOffset = .zero
                self.overlay = overlay
            }
    }

    private func reset() {
        overlay = nil
        activeZoomPageID = nil
    }

    private func clampedGestureTranslation(_ translation: CGSize, for overlay: MangaVerticalZoomOverlayState) -> CGSize {
        let proposed = CGSize(
            width: overlay.steadyOffset.width + translation.width,
            height: overlay.steadyOffset.height + translation.height
        )
        let clamped = clampedOffset(proposed, for: overlay)
        return CGSize(
            width: clamped.width - overlay.steadyOffset.width,
            height: clamped.height - overlay.steadyOffset.height
        )
    }

    private func clampedOffset(_ proposed: CGSize, for overlay: MangaVerticalZoomOverlayState) -> CGSize {
        let bounds = CGSize(
            width: max(0, (overlay.baseImageSize.width * overlay.steadyScale - overlay.baseImageSize.width) / 2),
            height: max(0, (overlay.baseImageSize.height * overlay.steadyScale - overlay.baseImageSize.height) / 2)
        )
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposed.width)),
            height: min(bounds.height, max(-bounds.height, proposed.height))
        )
    }
}
#endif
