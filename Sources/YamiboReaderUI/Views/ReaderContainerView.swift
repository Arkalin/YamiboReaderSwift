import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private enum ReaderChromeMode {
    case loading
    case error
    case visible
    case immersiveHidden

    var showsChrome: Bool {
        self != .immersiveHidden
    }
}

public struct ReaderContainerView: View {
    @StateObject private var model: ReaderContainerModel
    @StateObject private var verticalScrollCoordinator = ReaderVerticalScrollCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var showingCachePanel = false
    @State private var showingCacheProgress = false
    @State private var showingWebJumpSheet = false
    @State private var showingChapterSheet = false
    @State private var chromeMode: ReaderChromeMode = .loading
    @State private var verticalScrollRequest: Int?
    @State private var progressPreviewPageIndex: Int?
    @State private var progressPreviewChapterTitle: String?
    @State private var isProgressPreviewVisible = false
    @State private var progressPreviewHideTask: Task<Void, Never>?
    @State private var verticalTapSuppressionUntil: CFTimeInterval = 0
    private let appModel: YamiboAppModel

    public init(context: ReaderLaunchContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: ReaderContainerModel(context: context, appContext: appModel.appContext))
        self.appModel = appModel
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                content

                if isProgressPreviewVisible {
                    ReaderChapterPreviewBubble(title: progressPreviewChapterTitle ?? "•••")
                        .padding(.bottom, chromeMode.showsChrome ? bottomInset + 118 : bottomInset + 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if chromeMode.showsChrome {
                    ReaderTopChrome(
                        model: model,
                        topInset: topInset,
                        onClose: closeReader,
                        onOpenForum: openInForum,
                        onRefresh: refreshReader
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if chromeMode.showsChrome {
                    ReaderBottomChrome(
                        model: model,
                        bottomInset: bottomInset,
                        onShowChapters: openChapterDrawer,
                        onShowWebJump: openWebJumpSheet,
                        onStepWeb: { delta in
                            Task { await jumpToWebView(model.visibleView + delta) }
                        },
                        onShowSettings: openSettings,
                        onShowCache: openCachePanel,
                        onJumpChapter: { delta in
                            jumpAdjacentChapter(delta)
                        },
                        onProgressPreviewChange: { value, isEditing in
                            handleProgressPreviewChange(value: value, isEditing: isEditing)
                        },
                        onProgressCommit: { value in
                            commitProgressSlider(value)
                        }
                    )
                }
            }
            .task {
                await model.prepare(layout: ReaderContainerLayout(width: proxy.size.width, height: proxy.size.height))
                updateChromeForContentState()
            }
            .onDisappear {
                progressPreviewHideTask?.cancel()
                Task { await model.saveProgress() }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showingChapterSheet) {
                ReaderChapterSheet(model: model) { chapter in
                    jumpToChapter(chapter)
                }
            }
            .sheet(isPresented: $showingCachePanel) {
                ReaderCachePanel(model: model) {
                    showingCachePanel = false
                    showingCacheProgress = true
                }
            }
            .sheet(
                isPresented: $showingCacheProgress,
                onDismiss: {
                    if model.hasCacheOperationSession {
                        model.hideCacheProgress()
                    }
                }
            ) {
                ReaderCacheProgressSheet(model: model) {
                    showingCacheProgress = false
                }
            }
            .sheet(isPresented: $showingWebJumpSheet) {
                ReaderWebJumpSheet(model: model) { view in
                    Task { await jumpToWebView(view) }
                }
            }
            .statusBar(hidden: chromeMode == .immersiveHidden || !model.settings.showsSystemStatusBar)
            .onChange(of: model.isLoading) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.errorMessage) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.pages.count) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingSettings) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingCachePanel) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingCacheProgress) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingWebJumpSheet) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingChapterSheet) { _, _ in
                updateChromeForContentState()
            }
            .animation(.easeInOut(duration: 0.2), value: isProgressPreviewVisible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.pages.isEmpty {
            VStack(spacing: 12) {
                ProgressView("加载中…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage, model.pages.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                Button("重试", action: retryLoad)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.settings.readingMode == .paged {
            pagedContent
        } else {
            verticalContent
        }
    }

    private var pagedContent: some View {
        TabView(selection: $model.currentPageIndex) {
            ForEach(model.pages) { page in
                ReaderPageContent(
                    page: page,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    sessionState: model.sessionState
                )
                .tag(page.index)
                .padding(.horizontal, model.settings.horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: model.currentPageIndex) { _, newValue in
            model.updateCurrentPage(newValue)
        }
        .overlay {
            if !model.pages.isEmpty {
                ReaderPagedTapZones(
                    onPrevious: {
                        Task { await goRelativePage(-1) }
                    },
                    onToggleChrome: toggleChrome,
                    onNext: {
                        Task { await goRelativePage(1) }
                    }
                )
            }
        }
    }

    private var verticalContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.pages) { page in
                        ReaderPageContent(
                            page: page,
                            settings: model.settings,
                            refererURL: model.forumURL,
                            sessionState: model.sessionState
                        )
                        .id(page.index)
                        .padding(.horizontal, model.settings.horizontalPadding)
                        .padding(.top, page.index == 0 ? 16 : 0)
                        .onAppear {
                            model.updateCurrentPage(page.index)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .contentShape(Rectangle())
            .background(
                ReaderScrollViewResolver { scrollView in
                    verticalScrollCoordinator.attach(scrollView: scrollView)
                }
            )
            .simultaneousGesture(
                verticalScrollSuppressionGesture
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    handleVerticalTap()
                }
            )
            .onChange(of: verticalScrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(request, anchor: .top)
                }
                verticalScrollRequest = nil
            }
        }
    }

    private var backgroundColor: Color {
        readerThemeColor(for: model.settings.backgroundStyle, colorScheme: colorScheme)
    }

    private func retryLoad() {
        chromeMode = .visible
        Task { await model.loadCurrent(forceRefresh: false) }
    }

    private func refreshReader() {
        chromeMode = .visible
        Task { await model.loadCurrent(forceRefresh: true) }
    }

    private func openInForum() {
        chromeMode = .visible
        Task { await model.saveProgress() }
        appModel.dismissReader(openThreadInForum: model.forumURL)
    }

    private func closeReader() {
        chromeMode = .visible
        Task { await model.saveProgress() }
        appModel.dismissReader()
    }

    private func toggleChrome() {
        guard !model.pages.isEmpty else { return }
        guard !hasPresentedOverlay else { return }
        progressPreviewHideTask?.cancel()
        isProgressPreviewVisible = false
        withAnimation(.easeInOut(duration: 0.2)) {
            chromeMode = chromeMode == .immersiveHidden ? .visible : .immersiveHidden
        }
    }

    private func handleVerticalTap() {
        guard !model.pages.isEmpty else { return }
        let now = CACurrentMediaTime()
        if now <= verticalTapSuppressionUntil {
            verticalTapSuppressionUntil = now + 0.35
            _ = verticalScrollCoordinator.interruptScrollingIfNeeded()
            return
        }
        if verticalScrollCoordinator.shouldSuppressChromeToggle() {
            return
        }
        if verticalScrollCoordinator.interruptScrollingIfNeeded() {
            verticalTapSuppressionUntil = now + 0.35
            return
        }
        toggleChrome()
    }

    private var verticalScrollSuppressionGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
            }
            .onEnded { _ in
                verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
            }
    }

    private func openChapterDrawer() {
        chromeMode = .visible
        showingChapterSheet = true
    }

    private func openSettings() {
        chromeMode = .visible
        showingSettings = true
    }

    private func openCachePanel() {
        chromeMode = .visible
        if model.hasCacheOperationSession {
            model.showCacheProgressIfRunning()
            showingCacheProgress = true
        } else {
            showingCachePanel = true
        }
    }

    private func openWebJumpSheet() {
        chromeMode = .visible
        showingWebJumpSheet = true
    }

    private func updateChromeForContentState() {
        guard !hasPresentedOverlay else {
            chromeMode = .visible
            return
        }

        if model.isLoading && model.pages.isEmpty {
            chromeMode = .loading
            return
        }

        if model.errorMessage != nil && model.pages.isEmpty {
            chromeMode = .error
            return
        }

        guard !model.pages.isEmpty else { return }

        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }

        if chromeMode != .immersiveHidden {
            withAnimation(.easeInOut(duration: 0.2)) {
                chromeMode = .immersiveHidden
            }
        }
    }

    private func commitProgressSlider(_ value: Double) {
        let targetIndex = model.targetRenderedPageIndex(forProgressValue: value)
        model.jumpToRenderedPage(targetIndex)
        showProgressPreview(for: targetIndex, autoHide: true)
        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }
    }

    private func jumpAdjacentChapter(_ delta: Int) {
        model.jumpToAdjacentChapter(delta)
        showProgressPreview(for: model.currentPageIndex, autoHide: true)
        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }
    }

    private func jumpToChapter(_ chapter: ReaderChapter) {
        model.jumpToChapter(chapter)
        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }
    }

    private func jumpToWebView(_ view: Int) async {
        chromeMode = .visible
        await model.jumpToWebView(view)
        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }
    }

    private func goRelativePage(_ delta: Int) async {
        await model.jumpRelativePage(delta)
        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }
    }

    private var hasPresentedOverlay: Bool {
        showingSettings || showingCachePanel || showingCacheProgress || showingWebJumpSheet || showingChapterSheet
    }

    private func handleProgressPreviewChange(value: Double?, isEditing: Bool) {
        guard isEditing, let value else {
            hideProgressPreview(after: 0.8)
            return
        }

        let targetIndex = model.targetRenderedPageIndex(forProgressValue: value)
        showProgressPreview(for: targetIndex, autoHide: false)
    }

    private func showProgressPreview(for pageIndex: Int, autoHide: Bool) {
        progressPreviewHideTask?.cancel()
        progressPreviewPageIndex = pageIndex
        progressPreviewChapterTitle = model.chapterTitle(forRenderedPageIndex: pageIndex) ?? "•••"
        withAnimation(.easeInOut(duration: 0.2)) {
            isProgressPreviewVisible = true
        }
        if autoHide {
            hideProgressPreview(after: 0.8)
        }
    }

    private func hideProgressPreview(after delay: TimeInterval) {
        progressPreviewHideTask?.cancel()
        progressPreviewHideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isProgressPreviewVisible = false
                }
            }
        }
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}

private final class ReaderVerticalScrollCoordinator: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    private weak var scrollView: UIScrollView?
    private weak var interruptionTapRecognizer: UITapGestureRecognizer?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var suppressChromeToggleUntil = CACurrentMediaTime()
    private var lastMotionTime = CACurrentMediaTime()
    private let motionSuppressionInterval: CFTimeInterval = 0.35

    func attach(scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        detachTapRecognizer()
        contentOffsetObservation = nil
        self.scrollView = scrollView
        installTapRecognizerIfNeeded()
        installContentOffsetObservationIfNeeded()
    }

    func interruptScrollingIfNeeded() -> Bool {
        guard let scrollView, scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            return false
        }

        let offset = scrollView.contentOffset
        scrollView.setContentOffset(offset, animated: false)
        lastMotionTime = CACurrentMediaTime()

        // Toggling scrollability reliably stops residual momentum from SwiftUI's backing scroll view.
        if scrollView.isDecelerating {
            scrollView.isScrollEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.setContentOffset(offset, animated: false)
        }

        return true
    }

    func shouldSuppressChromeToggle() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastMotionTime <= motionSuppressionInterval {
            suppressChromeToggleUntil = now
            return true
        }
        guard now <= suppressChromeToggleUntil else { return false }
        suppressChromeToggleUntil = now
        return true
    }

    private func installTapRecognizerIfNeeded() {
        guard let scrollView, interruptionTapRecognizer == nil else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleInterruptionTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        interruptionTapRecognizer = recognizer
    }

    private func installContentOffsetObservationIfNeeded() {
        guard let scrollView else { return }
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
            guard let self, let oldValue = change.oldValue, let newValue = change.newValue else { return }
            guard oldValue != newValue else { return }
            self.lastMotionTime = CACurrentMediaTime()
        }
    }

    private func detachTapRecognizer() {
        if let recognizer = interruptionTapRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        interruptionTapRecognizer = nil
    }

    @objc
    private func handleInterruptionTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard interruptScrollingIfNeeded() else { return }
        suppressChromeToggleUntil = CACurrentMediaTime() + motionSuppressionInterval
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }
}

private struct ReaderScrollViewResolver: UIViewRepresentable {
    let onResolve: (UIScrollView?) -> Void

    func makeUIView(context: Context) -> ReaderScrollViewResolverView {
        let view = ReaderScrollViewResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ReaderScrollViewResolverView, context: Context) {
        uiView.onResolve = onResolve
        uiView.resolveScrollViewIfNeeded()
    }
}

private final class ReaderScrollViewResolverView: UIView {
    var onResolve: ((UIScrollView?) -> Void)?
    private weak var resolvedScrollView: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveScrollViewIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveScrollViewIfNeeded()
    }

    func resolveScrollViewIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var candidate = self.superview
            var scrollView: UIScrollView?

            while let current = candidate {
                if let resolved = current as? UIScrollView {
                    scrollView = resolved
                    break
                }
                candidate = current.superview
            }

            guard scrollView !== self.resolvedScrollView else { return }
            self.resolvedScrollView = scrollView
            self.onResolve?(scrollView)
        }
    }
}

private struct ReaderPagedTapZones: View {
    let onPrevious: () -> Void
    let onToggleChrome: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tapZone(action: onPrevious)
                .frame(maxWidth: .infinity)
            tapZone(action: onToggleChrome)
                .frame(maxWidth: .infinity)
            tapZone(action: onNext)
                .frame(maxWidth: .infinity)
        }
    }

    private func tapZone(action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
#else
public struct ReaderContainerView: View {
    public let context: ReaderLaunchContext
    public let appModel: YamiboAppModel

    public init(context: ReaderLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        Text("Reader is available on iOS only.")
    }
}
#endif
