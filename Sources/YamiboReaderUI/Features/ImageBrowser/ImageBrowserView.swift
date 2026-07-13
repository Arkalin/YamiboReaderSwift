import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ImageBrowserItem: Identifiable {
    let id: String
    let source: YamiboImageSource
    let title: String
    /// Optional local-bytes-first loader (e.g. Like Library's user-retained
    /// image store). The page view tries this before falling back to the
    /// network image pipeline. Existing call sites omit it and behave
    /// exactly as before.
    let localDataProvider: (@Sendable () async -> Data?)?

    init(
        id: String,
        source: YamiboImageSource,
        title: String,
        localDataProvider: (@Sendable () async -> Data?)? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.localDataProvider = localDataProvider
    }
}

extension ImageBrowserItem: Equatable {
    static func == (lhs: ImageBrowserItem, rhs: ImageBrowserItem) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.title == rhs.title
    }
}

enum ImageBrowserMode: Equatable {
    case single
    case multiple
}

struct ImageBrowserView: View {
    let items: [ImageBrowserItem]
    let mode: ImageBrowserMode
    let coverActionsProvider: ImageBrowserCoverActionsProvider?
    let onJumpToOriginal: (() -> Void)?
    let onDismiss: () -> Void

    @State private var selectedItemID: String
    @State private var swipeDismissProgress: CGFloat = 0
    @State private var isSwipeDismissCommitted = false
    @State private var feedback: ImageBrowserFeedback?
    @State private var transientMessage: String?
    @State private var isPreparingAction = false
    @State private var coverActions: [ImageBrowserCoverAction] = []

    init(
        items: [ImageBrowserItem],
        initialItemID: String?,
        mode: ImageBrowserMode,
        coverActionsProvider: ImageBrowserCoverActionsProvider? = nil,
        onJumpToOriginal: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.mode = mode
        self.coverActionsProvider = coverActionsProvider
        self.onJumpToOriginal = onJumpToOriginal
        self.onDismiss = onDismiss
        _selectedItemID = State(initialValue: Self.initialSelection(in: items, initialItemID: initialItemID))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ImageBrowserContentView(
                items: items,
                mode: mode,
                selectedItemID: $selectedItemID,
                onSwipeDownProgressChange: { progress in
                    swipeDismissProgress = progress
                },
                onSwipeDownCommit: beginSwipeDownDismissCommit,
                onSwipeDownDismiss: commitSwipeDownDismiss
            )
            .ignoresSafeArea()

            ImageBrowserToolbar(
                title: currentItem?.title ?? "",
                canPerformImageAction: currentItem != nil && !isPreparingAction,
                isPreparingAction: isPreparingAction,
                swipeDismissProgress: swipeDismissProgress,
                isSwipeDismissCommitted: isSwipeDismissCommitted,
                copyImage: {
                    Task {
                        await copyImage()
                    }
                },
                shareable: currentShareable,
                saveImage: {
                    Task {
                        await saveImage()
                    }
                },
                coverActions: coverActions,
                performCoverAction: { action in
                    Task {
                        await performCoverAction(action)
                    }
                },
                onJumpToOriginal: onJumpToOriginal,
                onDismiss: onDismiss
            )
        }
        .modalTransitionStyle(.crossDissolve)
        .task {
            await reloadCoverActions()
        }
        .alert(
            feedback?.title ?? "",
            isPresented: isFeedbackPresented,
            presenting: feedback
        ) { feedback in
            if feedback.offersOpenSettings {
                Button(L10n.string("favorites.updates.notifications_open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } else {
                Button(L10n.string("common.done"), role: .cancel) {}
            }
        } message: { feedback in
            Text(feedback.message)
        }
        .forumTransientMessage(transientMessage) {
            transientMessage = nil
        }
        .accessibilityIdentifier("reader-image-browser")
    }

    private var currentItem: ImageBrowserItem? {
        items.first { $0.id == selectedItemID } ?? items.first
    }

    private var currentShareable: ImageBrowserShareableImage? {
        guard let currentItem else { return nil }
        return ImageBrowserShareableImage(
            source: currentItem.source,
            fileExtension: preferredImageExtension(for: currentItem),
            title: currentItem.title
        )
    }

    private var isFeedbackPresented: Binding<Bool> {
        Binding(
            get: { feedback != nil },
            set: { isPresented in
                if !isPresented {
                    feedback = nil
                }
            }
        )
    }

    private static func initialSelection(in items: [ImageBrowserItem], initialItemID: String?) -> String {
        if let initialItemID,
           items.contains(where: { $0.id == initialItemID }) {
            return initialItemID
        }
        return items.first?.id ?? ""
    }

    private func copyImage() async {
        await performImageAction { item in
            let data = try await imageData(for: item)
            guard let image = UIImage(data: data) else {
                throw ImageBrowserActionError.invalidImageData
            }
            UIPasteboard.general.image = image
            transientMessage = L10n.string("image.copy_success_message")
        }
    }

    private func saveImage() async {
        await performImageAction { item in
            let data = try await imageData(for: item)
            let saver = MangaImagePhotoSaver()
            try await saver.saveImageData(data)
            transientMessage = L10n.string("image.save_success_message")
        }
    }

    private func reloadCoverActions() async {
        guard let coverActionsProvider else { return }
        coverActions = await coverActionsProvider()
    }

    private func performCoverAction(_ coverAction: ImageBrowserCoverAction) async {
        await performImageAction { item in
            guard let message = try await coverAction.perform(item.source) else {
                throw ImageBrowserActionError.invalidImageData
            }
            transientMessage = message
        }
        await reloadCoverActions()
    }

    private func performImageAction(_ action: @escaping (ImageBrowserItem) async throws -> Void) async {
        guard !isPreparingAction, let currentItem else { return }
        isPreparingAction = true
        defer {
            isPreparingAction = false
        }
        do {
            try await action(currentItem)
        } catch MangaImagePhotoSaveError.authorizationDenied {
            feedback = .photoPermissionDenied()
        } catch {
            YamiboLog.reader.error("Image browser action failed for item \(currentItem.id): \(error)")
            feedback = .failure(message: L10n.string("image.action_failed"))
        }
    }

    private func imageData(for item: ImageBrowserItem) async throws -> Data {
        try await YamiboImagePipeline.shared.data(for: item.source)
    }

    private func preferredImageExtension(for item: ImageBrowserItem) -> String {
        let ext = item.source.url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ext.isEmpty, ext.count <= 8 else { return "jpg" }
        return ext
    }

    private func beginSwipeDownDismissCommit() {
        guard !isSwipeDismissCommitted else { return }
        isSwipeDismissCommitted = true
        swipeDismissProgress = 1
    }

    private func commitSwipeDownDismiss() {
        isSwipeDismissCommitted = true
        onDismiss()
    }
}

private struct ImageBrowserContentView: View {
    let items: [ImageBrowserItem]
    let mode: ImageBrowserMode
    @Binding var selectedItemID: String
    let onSwipeDownProgressChange: (CGFloat) -> Void
    let onSwipeDownCommit: () -> Void
    let onSwipeDownDismiss: () -> Void

    var body: some View {
        if mode == .multiple, items.count > 1 {
            TabView(selection: $selectedItemID) {
                ForEach(items) { item in
                    ImageBrowserPageView(
                        item: item,
                        onSwipeDownProgressChange: onSwipeDownProgressChange,
                        onSwipeDownCommit: onSwipeDownCommit,
                        onSwipeDownDismiss: onSwipeDownDismiss
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        } else if let item = items.first {
            ImageBrowserPageView(
                item: item,
                onSwipeDownProgressChange: onSwipeDownProgressChange,
                onSwipeDownCommit: onSwipeDownCommit,
                onSwipeDownDismiss: onSwipeDownDismiss
            )
        } else {
            ImageBrowserFailureView(retry: nil)
        }
    }
}

private struct ImageBrowserPageView: View {
    let item: ImageBrowserItem
    let onSwipeDownProgressChange: (CGFloat) -> Void
    let onSwipeDownCommit: () -> Void
    let onSwipeDownDismiss: () -> Void

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                ImageBrowserZoomableImageView(
                    image: image,
                    onSwipeDownProgressChange: onSwipeDownProgressChange,
                    onSwipeDownCommit: onSwipeDownCommit,
                    onSwipeDownDismiss: onSwipeDownDismiss
                )
            } else if didFail {
                ImageBrowserFailureView {
                    didFail = false
                    attempt += 1
                }
            } else {
                ProgressView(L10n.string("image.loading"))
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .task(id: "\(item.source.cacheKey)#\(attempt)") {
            await load()
        }
    }

    private func load() async {
        guard image == nil else { return }
        if let localDataProvider = item.localDataProvider,
           let localData = await localDataProvider(),
           let localImage = UIImage(data: localData) {
            image = localImage
            return
        }
        do {
            image = try await YamiboUIImagePipeline.shared.image(for: item.source)
        } catch {
            YamiboLog.reader.warning("Failed to load image for browser item \(item.id): \(error)")
            didFail = true
        }
    }
}

private struct ImageBrowserFailureView: View {
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Label(L10n.string("image.load_failed"), systemImage: "photo")
                .foregroundStyle(.white.opacity(0.8))

            if let retry {
                Button(action: retry) {
                    Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(24)
    }
}

private struct ImageBrowserToolbar: View {
    let title: String
    let canPerformImageAction: Bool
    let isPreparingAction: Bool
    let swipeDismissProgress: CGFloat
    let isSwipeDismissCommitted: Bool
    let copyImage: () -> Void
    let shareable: ImageBrowserShareableImage?
    let saveImage: () -> Void
    let coverActions: [ImageBrowserCoverAction]
    let performCoverAction: (ImageBrowserCoverAction) -> Void
    let onJumpToOriginal: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 12)

                Menu {
                    Button(action: copyImage) {
                        Label(L10n.string("image.copy"), systemImage: "doc.on.doc")
                    }

                    if let shareable {
                        ShareLink(item: shareable, preview: SharePreview(shareable.title)) {
                            Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(action: saveImage) {
                        Label(L10n.string("image.save_to_photos"), systemImage: "square.and.arrow.down")
                    }

                    if !coverActions.isEmpty {
                        Divider()
                        ForEach(coverActions) { action in
                            Button {
                                performCoverAction(action)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }

                    if let onJumpToOriginal {
                        Divider()
                        Button(action: onJumpToOriginal) {
                            Label(L10n.string("likes.jump_to_original"), systemImage: "book.closed")
                        }
                    }
                } label: {
                    Image(systemName: isPreparingAction ? "hourglass" : "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.58), in: Circle())
                }
                .disabled(!canPerformImageAction)
                .accessibilityLabel(L10n.string("common.more"))

                Button(action: onDismiss) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.58), in: Circle())
                }
                .accessibilityLabel(L10n.string("common.done"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.62), .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            Spacer(minLength: 0)
        }
        .opacity(1 - min(swipeDismissProgress * 1.4, 1))
        .allowsHitTesting(!isSwipeDismissCommitted)
    }
}

private enum ImageBrowserActionError: Error {
    case invalidImageData
}

private struct ImageBrowserFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var offersOpenSettings = false

    static func failure(message: String) -> ImageBrowserFeedback {
        ImageBrowserFeedback(title: L10n.string("common.operation_failed"), message: message)
    }

    static func photoPermissionDenied() -> ImageBrowserFeedback {
        ImageBrowserFeedback(
            title: L10n.string("image.save_photo_permission_denied_title"),
            message: L10n.string("image.save_photo_permission_denied"),
            offersOpenSettings: true
        )
    }
}

/// Lazily materializes the shared image when the user commits to sharing:
/// ShareLink drives the export, so no temp file or spinner state is needed
/// up front. The exported file lands in the system temporary directory and
/// is reclaimed by the OS.
private struct ImageBrowserShareableImage: Transferable {
    let source: YamiboImageSource
    let fileExtension: String
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .image) { shareable in
            let data = try await YamiboImagePipeline.shared.data(for: shareable.source)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(shareable.fileExtension)
            try data.write(to: fileURL, options: .atomic)
            return SentTransferredFile(fileURL)
        }
    }
}

private struct ImageBrowserZoomableImageView: View {
    let image: UIImage
    let onSwipeDownProgressChange: (CGFloat) -> Void
    let onSwipeDownCommit: () -> Void
    let onSwipeDownDismiss: () -> Void

    private let doubleTapZoomScale: CGFloat = 2.6
    private let maximumZoomScale: CGFloat = 5

    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    @State private var swipeDismissTranslation: CGFloat = 0
    @State private var swipeDismissExitOffset: CGFloat = 0
    @State private var imageOpacity: CGFloat = 1
    @State private var isSwipeDismissCommitted = false

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(displayScale)
                .offset(
                    x: steadyOffset.width + gestureOffset.width,
                    y: steadyOffset.height + gestureOffset.height + swipeDismissTranslation + swipeDismissExitOffset
                )
                .opacity(imageOpacity)
                .contentShape(Rectangle())
                .simultaneousGesture(doubleTapGesture(containerSize: containerSize))
                .simultaneousGesture(magnifyGesture(containerSize: containerSize))
                .simultaneousGesture(
                    zoomPanGesture(containerSize: containerSize),
                    including: zoomPanGestureMask
                )
                .simultaneousGesture(
                    swipeDismissDragGesture(containerSize: containerSize),
                    including: swipeDismissGestureMask
                )
                .onChange(of: containerSize) { _, newValue in
                    clampSteadyOffset(containerSize: newValue)
                }
        }
    }

    private var zoomScale: CGFloat {
        clampedScale(steadyScale * gestureScale)
    }

    /// Whether the image is zoomed enough that a one-finger drag should pan the zoomed
    /// content instead of paging between images or swiping down to dismiss.
    private var isZoomPanActive: Bool {
        zoomScale > 1.01
    }

    /// Detaches the pan gesture entirely (rather than letting it no-op) while unzoomed so it
    /// never competes with `TabView(.page)`'s own horizontal swipe for the same touch.
    private var zoomPanGestureMask: GestureMask {
        isZoomPanActive ? .gesture : .subviews
    }

    /// Detaches the swipe-to-dismiss gesture entirely while zoomed, since panning takes over
    /// at that point; see `zoomPanGestureMask` for the complementary case.
    private var swipeDismissGestureMask: GestureMask {
        isZoomPanActive ? .subviews : .gesture
    }

    private var displayScale: CGFloat {
        zoomScale * ImageBrowserSwipeDismissGesture.imageScale(for: swipeDismissProgress)
    }

    private var swipeDismissProgress: CGFloat {
        ImageBrowserSwipeDismissGesture.progress(for: swipeDismissTranslation)
    }

    private func doubleTapGesture(containerSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded { value in
                guard !isSwipeDismissCommitted else { return }
                if steadyScale > 1.05 {
                    resetZoom(containerSize: containerSize, animated: true)
                } else {
                    zoomIn(to: value.location, containerSize: containerSize)
                }
            }
    }

    private func magnifyGesture(containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isSwipeDismissCommitted else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                gestureScale = nextScale / max(steadyScale, 0.001)
                steadyOffset = clampedOffset(
                    steadyOffset,
                    scale: nextScale,
                    containerSize: containerSize
                )
            }
            .onEnded { value in
                guard !isSwipeDismissCommitted else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                steadyScale = nextScale
                gestureScale = 1
                if nextScale <= 1.01 {
                    resetZoom(containerSize: containerSize, animated: true)
                } else {
                    steadyOffset = clampedOffset(
                        steadyOffset,
                        scale: nextScale,
                        containerSize: containerSize
                    )
                }
            }
    }

    private func zoomPanGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isSwipeDismissCommitted, isZoomPanActive else { return }
                updateZoomDrag(value.translation, containerSize: containerSize)
            }
            .onEnded { value in
                guard !isSwipeDismissCommitted, isZoomPanActive else { return }
                endZoomDrag(value.translation, containerSize: containerSize)
            }
    }

    private func swipeDismissDragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: ImageBrowserSwipeDismissGesture.minimumRecognitionDistance)
            .onChanged { value in
                guard !isSwipeDismissCommitted, !isZoomPanActive else { return }
                updateSwipeDismissDrag(value.translation)
            }
            .onEnded { value in
                guard !isSwipeDismissCommitted, !isZoomPanActive else { return }
                endSwipeDismissDrag(value, containerSize: containerSize)
            }
    }

    private func updateZoomDrag(_ translation: CGSize, containerSize: CGSize) {
        let proposed = CGSize(
            width: steadyOffset.width + translation.width,
            height: steadyOffset.height + translation.height
        )
        let clamped = clampedOffset(
            proposed,
            scale: zoomScale,
            containerSize: containerSize
        )
        gestureOffset = CGSize(
            width: clamped.width - steadyOffset.width,
            height: clamped.height - steadyOffset.height
        )
    }

    private func endZoomDrag(_ translation: CGSize, containerSize: CGSize) {
        let proposed = CGSize(
            width: steadyOffset.width + translation.width,
            height: steadyOffset.height + translation.height
        )
        steadyOffset = clampedOffset(
            proposed,
            scale: steadyScale,
            containerSize: containerSize
        )
        gestureOffset = .zero
    }

    private func updateSwipeDismissDrag(_ translation: CGSize) {
        let dismissTranslation = CGPoint(x: translation.width, y: translation.height)
        guard ImageBrowserSwipeDismissGesture.canBegin(
            translation: dismissTranslation,
            zoomScale: zoomScale,
            minimumZoomScale: 1
        ) else {
            resetSwipeDismissTracking(animated: true)
            return
        }
        swipeDismissTranslation = max(translation.height, 0)
        onSwipeDownProgressChange(swipeDismissProgress)
    }

    private func endSwipeDismissDrag(_ value: DragGesture.Value, containerSize: CGSize) {
        let translation = CGPoint(
            x: value.translation.width,
            y: value.translation.height
        )
        let velocity = CGPoint(
            x: value.velocity.width,
            y: value.velocity.height
        )

        if ImageBrowserSwipeDismissGesture.shouldDismiss(
            translation: translation,
            velocity: velocity,
            zoomScale: zoomScale,
            minimumZoomScale: 1
        ) {
            commitSwipeDismiss(translationY: translation.y, containerSize: containerSize)
        } else {
            resetSwipeDismissTracking(animated: true)
        }
    }

    private func zoomIn(to location: CGPoint, containerSize: CGSize) {
        let targetScale = min(maximumZoomScale, doubleTapZoomScale)
        let imageFrame = imageFrame(containerSize: containerSize)
        let targetLocation = imageFrame.contains(location)
            ? location
            : CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let proposedOffset = CGSize(
            width: -(targetLocation.x - center.x) * targetScale,
            height: -(targetLocation.y - center.y) * targetScale
        )

        withAnimation(.easeOut(duration: 0.2)) {
            steadyScale = targetScale
            gestureScale = 1
            steadyOffset = clampedOffset(
                proposedOffset,
                scale: targetScale,
                containerSize: containerSize
            )
            gestureOffset = .zero
        }
    }

    private func resetZoom(containerSize: CGSize, animated: Bool) {
        let updates = {
            steadyScale = 1
            gestureScale = 1
            steadyOffset = .zero
            gestureOffset = .zero
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), updates)
        } else {
            updates()
        }
        clampSteadyOffset(containerSize: containerSize)
    }

    private func resetSwipeDismissTracking(animated: Bool) {
        guard swipeDismissTranslation != 0 else {
            onSwipeDownProgressChange(0)
            return
        }

        let updates = {
            swipeDismissTranslation = 0
        }
        if animated {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86), updates)
        } else {
            updates()
        }
        onSwipeDownProgressChange(0)
    }

    private func commitSwipeDismiss(translationY: CGFloat, containerSize: CGSize) {
        guard !isSwipeDismissCommitted else { return }
        isSwipeDismissCommitted = true
        onSwipeDownCommit()
        onSwipeDownProgressChange(1)

        let imageHeight = imageFrame(containerSize: containerSize).height
        let exitDistance = max(
            containerSize.height - max(translationY, 0) + imageHeight * 0.35,
            containerSize.height * 0.45
        )
        withAnimation(.easeIn(duration: 0.18)) {
            swipeDismissTranslation = max(translationY, 0)
            swipeDismissExitOffset = exitDistance
            imageOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            onSwipeDownDismiss()
        }
    }

    private func clampSteadyOffset(containerSize: CGSize) {
        steadyOffset = clampedOffset(
            steadyOffset,
            scale: steadyScale,
            containerSize: containerSize
        )
        gestureOffset = .zero
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(maximumZoomScale, max(1, scale))
    }

    private func clampedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        containerSize: CGSize
    ) -> CGSize {
        let bounds = dragBounds(scale: scale, containerSize: containerSize)
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposed.width)),
            height: min(bounds.height, max(-bounds.height, proposed.height))
        )
    }

    private func dragBounds(scale: CGFloat, containerSize: CGSize) -> CGSize {
        let imageSize = imageFrame(containerSize: containerSize).size
        return CGSize(
            width: max(0, (imageSize.width * scale - containerSize.width) / 2),
            height: max(0, (imageSize.height * scale - containerSize.height) / 2)
        )
    }

    private func imageFrame(containerSize: CGSize) -> CGRect {
        ImageContentGeometry.aspectFitFrame(
            imageSize: image.size,
            containerSize: containerSize
        )
    }
}
#endif
