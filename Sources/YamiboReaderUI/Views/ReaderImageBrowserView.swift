import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderImageBrowserView: View {
    let url: URL
    let title: String
    let refererURL: URL
    let sessionState: SessionState
    let onDismiss: () -> Void

    @StateObject private var loader: ReaderImageLoader
    @State private var swipeDismissProgress: CGFloat = 0
    @State private var isSwipeDismissCommitted = false

    init(
        url: URL,
        title: String,
        refererURL: URL,
        sessionState: SessionState,
        onDismiss: @escaping () -> Void
    ) {
        self.url = url
        self.title = title
        self.refererURL = refererURL
        self.sessionState = sessionState
        self.onDismiss = onDismiss
        _loader = StateObject(
            wrappedValue: ReaderImageLoader(
                url: url,
                refererURL: refererURL,
                sessionState: sessionState
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
        .accessibilityIdentifier("reader-image-browser")
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

private struct ReaderZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onSwipeDownProgressChange: (CGFloat) -> Void
    let onSwipeDownCommit: () -> Void
    let onSwipeDownDismiss: () -> Void

    func makeUIView(context: Context) -> ReaderZoomableImageUIView {
        let view = ReaderZoomableImageUIView()
        view.scrollView.delegate = context.coordinator
        view.onSwipeDownProgressChange = onSwipeDownProgressChange
        view.onSwipeDownCommit = onSwipeDownCommit
        view.onSwipeDownDismiss = onSwipeDownDismiss
        context.coordinator.zoomView = view
        return view
    }

    func updateUIView(_ uiView: ReaderZoomableImageUIView, context: Context) {
        uiView.onSwipeDownProgressChange = onSwipeDownProgressChange
        uiView.onSwipeDownCommit = onSwipeDownCommit
        uiView.onSwipeDownDismiss = onSwipeDownDismiss
        uiView.setImage(image)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var zoomView: ReaderZoomableImageUIView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomView?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomView?.centerImage()
        }
    }
}

private final class ReaderZoomableImageUIView: UIView, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let imageView = UIImageView()
    var onSwipeDownProgressChange: ((CGFloat) -> Void)?
    var onSwipeDownCommit: (() -> Void)?
    var onSwipeDownDismiss: (() -> Void)?

    private var currentImage: UIImage?
    private var isSwipeDismissTracking = false
    private var isSwipeDismissCommitted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateImageFrame(resetZoom: false)
        centerImage()
    }

    func setImage(_ image: UIImage) {
        guard currentImage !== image else { return }
        currentImage = image
        imageView.image = image
        updateImageFrame(resetZoom: true)
    }

    func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
        scrollView.contentSize = frame.size
    }

    private func configureViewHierarchy() {
        backgroundColor = .black

        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        scrollView.addGestureRecognizer(dismissPan)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateImageFrame(resetZoom: Bool) {
        guard let image = currentImage,
              bounds.width > 0,
              bounds.height > 0,
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let fitScale = min(widthScale, heightScale)
        let fittedSize = CGSize(
            width: image.size.width * fitScale,
            height: image.size.height * fitScale
        )
        if resetZoom {
            scrollView.zoomScale = 1
        }
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerImage()
    }

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        let location = recognizer.location(in: imageView)
        let zoomScale = min(scrollView.maximumZoomScale, 2.6)
        let zoomSize = CGSize(
            width: scrollView.bounds.width / zoomScale,
            height: scrollView.bounds.height / zoomScale
        )
        let zoomRect = CGRect(
            x: location.x - zoomSize.width / 2,
            y: location.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )
        scrollView.zoom(to: zoomRect, animated: true)
    }

    @objc
    private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        switch recognizer.state {
        case .began, .changed:
            guard ReaderImageBrowserDismissGesture.canBegin(
                translation: translation,
                zoomScale: scrollView.zoomScale,
                minimumZoomScale: scrollView.minimumZoomScale
            ) else {
                resetSwipeDismissTracking(animated: true)
                return
            }
            isSwipeDismissTracking = true
            applySwipeDismissTransform(translationY: translation.y)
        case .ended:
            if ReaderImageBrowserDismissGesture.shouldDismiss(
                translation: translation,
                velocity: velocity,
                zoomScale: scrollView.zoomScale,
                minimumZoomScale: scrollView.minimumZoomScale
            ) {
                commitSwipeDismiss(translationY: translation.y)
            } else {
                resetSwipeDismissTracking(animated: true)
            }
        case .cancelled, .failed:
            resetSwipeDismissTracking(animated: true)
        default:
            break
        }
    }

    private func applySwipeDismissTransform(translationY: CGFloat) {
        guard !isSwipeDismissCommitted else { return }
        let progress = ReaderImageBrowserDismissGesture.progress(for: translationY)
        let scale = ReaderImageBrowserDismissGesture.imageScale(for: progress)
        imageView.transform = CGAffineTransform(translationX: 0, y: max(translationY, 0))
            .scaledBy(x: scale, y: scale)
        scrollView.backgroundColor = .clear
        backgroundColor = .clear
        onSwipeDownProgressChange?(progress)
    }

    private func resetSwipeDismissTracking(animated: Bool) {
        guard isSwipeDismissTracking || imageView.transform != .identity else { return }
        isSwipeDismissTracking = false
        let updates = {
            self.imageView.transform = .identity
            self.backgroundColor = .black
            self.scrollView.backgroundColor = .black
        }
        let completion: (Bool) -> Void = { _ in
            self.onSwipeDownProgressChange?(0)
        }
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: updates,
                completion: completion
            )
        } else {
            updates()
            completion(true)
        }
    }

    private func commitSwipeDismiss(translationY: CGFloat) {
        guard !isSwipeDismissCommitted else { return }
        isSwipeDismissCommitted = true
        isSwipeDismissTracking = false
        onSwipeDownCommit?()
        onSwipeDownProgressChange?(1)
        let exitDistance = max(bounds.height - max(translationY, 0) + imageView.bounds.height * 0.35, bounds.height * 0.45)
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: {
                self.imageView.transform = self.imageView.transform.translatedBy(x: 0, y: exitDistance)
                self.imageView.alpha = 0
            },
            completion: { _ in
                self.onSwipeDownDismiss?()
            }
        )
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
              gestureRecognizer.view === scrollView else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        return ReaderImageBrowserDismissGesture.canBegin(
            translation: panGesture.translation(in: self),
            zoomScale: scrollView.zoomScale,
            minimumZoomScale: scrollView.minimumZoomScale
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
#endif
