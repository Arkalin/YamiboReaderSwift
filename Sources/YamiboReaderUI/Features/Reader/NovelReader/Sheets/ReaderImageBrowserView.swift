import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderImageBrowserView: View {
    let url: URL
    let title: String
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
    let onDismiss: () -> Void

    @StateObject private var loader: ReaderImageLoader
    @State private var swipeDismissProgress: CGFloat = 0
    @State private var isSwipeDismissCommitted = false
    @State private var feedback: ReaderImageBrowserFeedback?
    @State private var shareItem: ReaderImageBrowserShareItem?
    @State private var isPreparingAction = false

    init(
        url: URL,
        title: String,
        refererURL: URL,
        imageDataLoader: any NovelInlineImageDataLoading,
        imageCacheNamespace: NovelInlineImageCacheNamespace,
        onDismiss: @escaping () -> Void
    ) {
        self.url = url
        self.title = title
        self.refererURL = refererURL
        self.imageDataLoader = imageDataLoader
        self.imageCacheNamespace = imageCacheNamespace
        self.onDismiss = onDismiss
        _loader = StateObject(
            wrappedValue: ReaderImageLoader(
                url: url,
                refererURL: refererURL,
                imageDataLoader: imageDataLoader,
                imageCacheNamespace: imageCacheNamespace
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isSwipeDismissCommitted ? 0 : ReaderImageBrowserDismissGesture.backgroundOpacity(for: swipeDismissProgress))
                .ignoresSafeArea()

            if let image = loader.image {
                ReaderZoomableImageView(
                    image: image,
                    onSwipeDownProgressChange: { progress in
                        swipeDismissProgress = progress
                    },
                    onSwipeDownCommit: beginSwipeDownDismissCommit,
                    onSwipeDownDismiss: commitSwipeDownDismiss
                )
                    .ignoresSafeArea()
            } else if loader.didFail {
                VStack(spacing: 12) {
                    Label(L10n.string("image.load_failed"), systemImage: "photo")
                        .foregroundStyle(.white.opacity(0.8))

                    Button {
                        Task {
                            await loader.retry()
                        }
                    } label: {
                        Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(24)
            } else {
                ProgressView(L10n.string("image.loading"))
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 12)

                    Menu {
                        Button {
                            Task {
                                await copyImage()
                            }
                        } label: {
                            Label(L10n.string("image.copy"), systemImage: "doc.on.doc")
                        }

                        Button {
                            Task {
                                await prepareShare()
                            }
                        } label: {
                            Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
                        }

                        Button {
                            Task {
                                await saveImage()
                            }
                        } label: {
                            Label(L10n.string("image.save_to_photos"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: isPreparingAction ? "hourglass" : "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .disabled(isPreparingAction || loader.didFail)
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
        .background(Color.clear)
        .task {
            await loader.loadIfNeeded()
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text(L10n.string("common.done")))
            )
        }
        .sheet(item: $shareItem) { item in
            ReaderImageBrowserActivityView(activityItems: [item.fileURL]) {
                try? FileManager.default.removeItem(at: item.fileURL)
                shareItem = nil
            }
        }
        .accessibilityIdentifier("reader-image-browser")
    }

    private func copyImage() async {
        await performImageAction {
            let data = try await imageData()
            guard let image = UIImage(data: data) else {
                throw ReaderImageBrowserActionError.invalidImageData
            }
            UIPasteboard.general.image = image
            feedback = .success(
                title: L10n.string("image.copy_success_title"),
                message: L10n.string("image.copy_success_message")
            )
        }
    }

    private func prepareShare() async {
        await performImageAction {
            let data = try await imageData()
            guard UIImage(data: data) != nil else {
                throw ReaderImageBrowserActionError.invalidImageData
            }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(preferredImageExtension)
            try data.write(to: fileURL, options: .atomic)
            shareItem = ReaderImageBrowserShareItem(fileURL: fileURL)
        }
    }

    private func saveImage() async {
        await performImageAction {
            let data = try await imageData()
            let saver = MangaImagePhotoSaver()
            try await saver.saveImageData(data)
            feedback = .success(
                title: L10n.string("image.save_success_title"),
                message: L10n.string("image.save_success_message")
            )
        }
    }

    private func performImageAction(_ action: @escaping () async throws -> Void) async {
        guard !isPreparingAction else { return }
        isPreparingAction = true
        defer {
            isPreparingAction = false
        }
        do {
            try await action()
        } catch MangaImagePhotoSaveError.authorizationDenied {
            feedback = .failure(message: L10n.string("image.save_photo_permission_denied"))
        } catch {
            feedback = .failure(message: L10n.string("image.action_failed"))
        }
    }

    private func imageData() async throws -> Data {
        try await imageDataLoader.imageData(for: url, refererURL: refererURL)
    }

    private var preferredImageExtension: String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum ReaderImageBrowserActionError: Error {
    case invalidImageData
}

private struct ReaderImageBrowserFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func success(title: String, message: String) -> ReaderImageBrowserFeedback {
        ReaderImageBrowserFeedback(title: title, message: message)
    }

    static func failure(message: String) -> ReaderImageBrowserFeedback {
        ReaderImageBrowserFeedback(title: L10n.string("common.operation_failed"), message: message)
    }
}

private struct ReaderImageBrowserShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ReaderImageBrowserActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private struct ReaderZoomableImageView: View {
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
                .simultaneousGesture(dragGesture(containerSize: containerSize))
                .onChange(of: containerSize) { _, newValue in
                    clampSteadyOffset(containerSize: newValue)
                }
        }
    }

    private var zoomScale: CGFloat {
        clampedScale(steadyScale * gestureScale)
    }

    private var displayScale: CGFloat {
        zoomScale * ReaderImageBrowserDismissGesture.imageScale(for: swipeDismissProgress)
    }

    private var swipeDismissProgress: CGFloat {
        ReaderImageBrowserDismissGesture.progress(for: swipeDismissTranslation)
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

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isSwipeDismissCommitted else { return }
                if zoomScale > 1.01 {
                    updateZoomDrag(value.translation, containerSize: containerSize)
                } else {
                    updateSwipeDismissDrag(value.translation)
                }
            }
            .onEnded { value in
                guard !isSwipeDismissCommitted else { return }
                if zoomScale > 1.01 {
                    endZoomDrag(value.translation, containerSize: containerSize)
                } else {
                    endSwipeDismissDrag(value, containerSize: containerSize)
                }
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
        guard ReaderImageBrowserDismissGesture.canBegin(
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

        if ReaderImageBrowserDismissGesture.shouldDismiss(
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
        ReaderImageHitTesting.aspectFitImageFrame(
            imageSize: image.size,
            containerSize: containerSize
        )
    }
}
#endif
