import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private struct ReaderVerticalViewportMetrics: Equatable {
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

private struct ReaderVerticalPositioningFingerprint: Equatable {
    let view: Int
    let pageCount: Int
    let pageIndex: Int
    let intraPageProgressBucket: Int
    let readingMode: ReaderReadingMode
}

private struct ReaderVerticalPageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ReaderTopChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReaderBottomChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    @State private var chromeState = ReaderChromeState()
    @State private var verticalScrollRequest: ReaderVerticalScrollRequest?
    @State private var verticalRestoreController = ReaderVerticalRestoreController()
    @State private var verticalRestoreRetryTask: Task<Void, Never>?
    @State private var verticalPageFrames: [Int: CGRect] = [:]
    @State private var lastVerticalPositioningFingerprint: ReaderVerticalPositioningFingerprint?
    @State private var progressPreviewPageIndex: Int?
    @State private var progressPreviewChapterTitle: String?
    @State private var isProgressPreviewVisible = false
    @State private var progressPreviewHideTask: Task<Void, Never>?
    @State private var verticalTapSuppressionUntil: CFTimeInterval = 0
    @State private var isDismissing = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0
    private let appModel: YamiboAppModel

    public init(context: ReaderLaunchContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: ReaderContainerModel(context: context, appContext: appModel.appContext))
        self.appModel = appModel
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)
            let currentLayout = readerLayout(
                proxy: proxy,
                topInset: topInset,
                bottomInset: bottomInset
            )

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                content

                if isProgressPreviewVisible {
                    ReaderChapterPreviewBubble(title: progressPreviewChapterTitle ?? "•••")
                        .padding(.bottom, chromeState.mode.showsChrome ? bottomInset + 118 : bottomInset + 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }

                if model.settings.readingMode == .paged && chromeState.mode.showsChrome {
                    VStack(spacing: 0) {
                        topChrome(topInset: topInset)
                        Spacer(minLength: 0)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        bottomChrome(bottomInset: bottomInset)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.settings.readingMode == .vertical && chromeState.mode.showsChrome {
                    topChrome(topInset: topInset)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.settings.readingMode == .vertical && chromeState.mode.showsChrome {
                    bottomChrome(bottomInset: bottomInset)
                }
            }
            .task {
                await model.prepare(layout: currentLayout)
                updateChromeForContentState()
            }
            .onChange(of: currentLayout) { _, newValue in
                model.updateLayout(newValue)
            }
            .onDisappear {
                progressPreviewHideTask?.cancel()
                verticalRestoreRetryTask?.cancel()
                syncVerticalViewportBeforeSave()
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
                } onSelectWebView: { view in
                    Task { await jumpToWebView(view) }
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
                .presentationDetents([.medium])
            }
            .statusBar(hidden: chromeState.mode == .immersiveHidden || !model.settings.showsSystemStatusBar)
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
            .onPreferenceChange(ReaderTopChromeHeightPreferenceKey.self) { value in
                topChromeHeight = value
            }
            .onPreferenceChange(ReaderBottomChromeHeightPreferenceKey.self) { value in
                bottomChromeHeight = value
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    ReaderScrollViewResolver { scrollView in
                        verticalScrollCoordinator.attach(scrollView: scrollView)
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)

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
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ReaderVerticalPageFramePreferenceKey.self,
                                    value: [page.index: geometry.frame(in: .named("readerVerticalViewport"))]
                                )
                            }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .coordinateSpace(name: "readerVerticalViewport")
            .contentShape(Rectangle())
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
                    scrollProxy.scrollTo(request.pageIndex, anchor: .top)
                }
                verticalScrollRequest = nil
                tryAdvanceVerticalRestore()
            }
            .onPreferenceChange(ReaderVerticalPageFramePreferenceKey.self) { frames in
                verticalPageFrames = frames
                tryAdvanceVerticalRestore()
                updateVerticalViewportPosition()
            }
            .onChange(of: verticalScrollCoordinator.viewportMetrics) { _, _ in
                tryAdvanceVerticalRestore()
                updateVerticalViewportPosition()
            }
        }
    }

    private var backgroundColor: Color {
        readerThemeColor(for: model.settings.backgroundStyle, colorScheme: colorScheme)
    }

    @ViewBuilder
    private func topChrome(topInset: CGFloat) -> some View {
        ReaderTopChrome(
            model: model,
            topInset: topInset,
            onClose: closeReader,
            onOpenForum: openInForum,
            onRefresh: refreshReader
        )
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ReaderTopChromeHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
    }

    @ViewBuilder
    private func bottomChrome(bottomInset: CGFloat) -> some View {
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
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ReaderBottomChromeHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
    }

    private func readerLayout(proxy: GeometryProxy, topInset: CGFloat, bottomInset: CGFloat) -> ReaderContainerLayout {
        let horizontalPadding = max(model.settings.horizontalPadding, 0)
        let safeAreaInsets = ReaderLayoutInsets(
            top: topInset,
            bottom: bottomInset
        )
        let contentInsets = ReaderLayoutInsets(
            top: model.settings.readingMode == .vertical ? 16 : 0,
            leading: horizontalPadding,
            bottom: model.settings.readingMode == .vertical ? 24 : 0,
            trailing: horizontalPadding
        )
        let chromeInsets = ReaderLayoutInsets(
            top: model.settings.readingMode == .vertical && chromeState.mode.showsChrome ? max(topChromeHeight - topInset, 0) : 0,
            bottom: model.settings.readingMode == .vertical && chromeState.mode.showsChrome ? max(bottomChromeHeight - bottomInset, 0) : 0
        )
        return ReaderContainerLayout(
            containerSize: proxy.size,
            safeAreaInsets: safeAreaInsets,
            contentInsets: contentInsets,
            chromeInsets: chromeInsets,
            readingMode: model.settings.readingMode
        )
    }

    private func retryLoad() {
        chromeState.showChrome()
        Task { await model.loadCurrent(forceRefresh: false) }
    }

    private func refreshReader() {
        chromeState.showChrome()
        Task { await model.loadCurrent(forceRefresh: true) }
    }

    private func openInForum() {
        chromeState.showChrome()
        guard !isDismissing else { return }
        isDismissing = true
        syncVerticalViewportBeforeSave()
        Task {
            await model.saveProgress()
            appModel.dismissReader(openThreadInForum: model.forumURL)
        }
    }

    private func closeReader() {
        chromeState.showChrome()
        guard !isDismissing else { return }
        isDismissing = true
        syncVerticalViewportBeforeSave()
        Task {
            await model.saveProgress()
            appModel.dismissReader()
        }
    }

    private func toggleChrome() {
        guard !model.pages.isEmpty else { return }
        guard !hasPresentedOverlay else { return }
        progressPreviewHideTask?.cancel()
        isProgressPreviewVisible = false
        withAnimation(.easeInOut(duration: 0.2)) {
            chromeState.toggleChrome()
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
                cancelVerticalRestoreForUserScroll()
                verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
            }
            .onEnded { _ in
                verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
            }
    }

    private func openChapterDrawer() {
        showingChapterSheet = true
    }

    private func openSettings() {
        showingSettings = true
    }

    private func openCachePanel() {
        if model.hasCacheOperationSession {
            model.showCacheProgressIfRunning()
            showingCacheProgress = true
        } else {
            showingCachePanel = true
        }
    }

    private func openWebJumpSheet() {
        guard model.maxView > 1 else { return }
        showingWebJumpSheet = true
    }

    private func updateChromeForContentState() {
        let previousState = chromeState
        var nextState = chromeState
        nextState.update(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            hasPages: !model.pages.isEmpty,
            hasPresentedOverlay: hasPresentedOverlay
        )
        if previousState.mode != nextState.mode {
            withAnimation(.easeInOut(duration: 0.2)) {
                chromeState = nextState
            }
        } else {
            chromeState = nextState
        }

        if model.isLoading && model.pages.isEmpty {
            lastVerticalPositioningFingerprint = nil
            return
        }

        if model.errorMessage != nil && model.pages.isEmpty {
            lastVerticalPositioningFingerprint = nil
            return
        }

        guard !model.pages.isEmpty else {
            lastVerticalPositioningFingerprint = nil
            return
        }

        if model.settings.readingMode == .vertical {
            let fingerprint = ReaderVerticalPositioningFingerprint(
                view: model.visibleView,
                pageCount: model.pages.count,
                pageIndex: model.currentPageIndex,
                intraPageProgressBucket: Int((model.currentPageIntraProgress * 1000).rounded()),
                readingMode: model.settings.readingMode
            )
            if lastVerticalPositioningFingerprint != fingerprint {
                lastVerticalPositioningFingerprint = fingerprint
                requestVerticalScrollToCurrentPage()
            }
        } else {
            lastVerticalPositioningFingerprint = nil
        }
    }

    private func commitProgressSlider(_ value: Double) {
        let targetIndex = model.targetRenderedPageIndex(forProgressValue: value)
        model.jumpToRenderedPage(targetIndex)
        showProgressPreview(for: targetIndex, autoHide: true)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func jumpAdjacentChapter(_ delta: Int) {
        model.jumpToAdjacentChapter(delta)
        showProgressPreview(for: model.currentPageIndex, autoHide: true)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func jumpToChapter(_ chapter: ReaderChapter) {
        model.jumpToChapter(chapter)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func jumpToWebView(_ view: Int) async {
        chromeState.showChrome()
        await model.jumpToWebView(view)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func goRelativePage(_ delta: Int) async {
        await model.jumpRelativePage(delta)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
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

    private func makeVerticalScrollRequest() -> ReaderVerticalScrollRequest {
        ReaderVerticalScrollRequest(
            pageIndex: model.currentPageIndex,
            intraPageProgress: model.currentPageIntraProgress
        )
    }

    private func requestVerticalScrollToCurrentPage() {
        let request = makeVerticalScrollRequest()
        beginVerticalRestoreScrolling(for: request)
        verticalScrollRequest = request
        scheduleVerticalRestoreRetry(for: request)
    }

    private func updateVerticalViewportPosition(force: Bool = false) {
        guard model.settings.readingMode == .vertical, !verticalPageFrames.isEmpty else { return }
        guard verticalRestoreController.canSampleViewport(now: CACurrentMediaTime()) else {
            return
        }

        let referenceLineY = verticalScrollCoordinator.referenceLineY
        guard let bestMatch = verticalPageFrames
            .filter({ $0.value.height > 0 })
            .min(by: { lhs, rhs in
                pageDistance(from: referenceLineY, to: lhs.value) < pageDistance(from: referenceLineY, to: rhs.value)
            }) else {
            return
        }

        let frame = bestMatch.value
        let intraPageProgress = min(max((referenceLineY - frame.minY) / max(frame.height, 1), 0), 1)
        model.updateVerticalViewportPosition(pageIndex: bestMatch.key, intraPageProgress: intraPageProgress)
    }

    private func applyVerticalFineTune(for request: ReaderVerticalScrollRequest) {
        guard verticalRestoreController.scrollingRequest == request else { return }
        guard let frame = verticalPageFrames[request.pageIndex] else { return }
        verticalRestoreController.beginFineTuning(request)
        guard verticalScrollCoordinator.restoreOffset(
            to: frame,
            intraPageProgress: request.intraPageProgress
        ) else {
            verticalRestoreController.beginScrolling(to: request)
            return
        }
        verticalRestoreController.beginSettling(request, now: CACurrentMediaTime())
        verticalRestoreRetryTask?.cancel()
        verticalRestoreRetryTask = nil
    }

    private func tryAdvanceVerticalRestore() {
        refreshVerticalRestorePhase()
        guard let request = verticalRestoreController.scrollingRequest else { return }
        guard verticalScrollCoordinator.hasAttachedScrollView else {
            return
        }
        guard let frame = verticalPageFrames[request.pageIndex] else {
            return
        }
        guard frame.height > 0 else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            applyVerticalFineTune(for: request)
        }
    }

    private func syncVerticalViewportBeforeSave() {
        guard model.settings.readingMode == .vertical else { return }
        tryAdvanceVerticalRestore()
        guard verticalRestoreController.canSampleViewport(now: CACurrentMediaTime()) else {
            return
        }
        updateVerticalViewportPosition(force: true)
    }

    private func beginVerticalRestoreScrolling(for request: ReaderVerticalScrollRequest) {
        verticalRestoreController.beginScrolling(to: request)
    }

    private func refreshVerticalRestorePhase(now: CFTimeInterval = CACurrentMediaTime()) {
        verticalRestoreController.refresh(now: now)
    }

    private func cancelVerticalRestoreForUserScroll() {
        guard verticalRestoreController.activeRequest != nil else { return }
        verticalRestoreController.cancel(now: CACurrentMediaTime())
        verticalRestoreRetryTask?.cancel()
        verticalRestoreRetryTask = nil
    }

    private func scheduleVerticalRestoreRetry(for request: ReaderVerticalScrollRequest) {
        verticalRestoreRetryTask?.cancel()
        verticalRestoreRetryTask = Task {
            for attempt in 1 ... 10 {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard verticalRestoreController.scrollingRequest == request else { return }
                    tryAdvanceVerticalRestore()
                    if verticalRestoreController.scrollingRequest == request, attempt == 3 || attempt == 6 || attempt == 9 {
                        verticalScrollRequest = request
                    }
                }
            }
        }
    }

    private func pageDistance(from referenceLineY: CGFloat, to frame: CGRect) -> CGFloat {
        if frame.contains(CGPoint(x: frame.midX, y: referenceLineY)) {
            return 0
        }
        if referenceLineY < frame.minY {
            return frame.minY - referenceLineY
        }
        return referenceLineY - frame.maxY
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
    @Published private(set) var viewportMetrics = ReaderVerticalViewportMetrics()

    private weak var scrollView: UIScrollView?
    private weak var interruptionTapRecognizer: UITapGestureRecognizer?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var currentViewportMetrics = ReaderVerticalViewportMetrics()
    private var pendingViewportMetrics: ReaderVerticalViewportMetrics?
    private var isViewportMetricsPublicationScheduled = false
    private var suppressChromeToggleUntil = CACurrentMediaTime()
    private var lastMotionTime = CACurrentMediaTime()
    private var isRestoringOffset = false
    private let motionSuppressionInterval: CFTimeInterval = 0.35

    func attach(scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        detachTapRecognizer()
        contentOffsetObservation = nil
        boundsObservation = nil
        self.scrollView = scrollView
        installTapRecognizerIfNeeded()
        installContentOffsetObservationIfNeeded()
        installBoundsObservationIfNeeded()
        syncViewportMetrics()
    }

    var referenceLineY: CGFloat {
        let height = max(currentViewportMetrics.viewportHeight, 0)
        guard height > 0 else { return 96 }
        return min(max(height * 0.22, 72), 160)
    }

    var hasAttachedScrollView: Bool {
        scrollView != nil
    }

    func interruptScrollingIfNeeded() -> Bool {
        guard let scrollView, scrollView.isDragging || scrollView.isDecelerating else {
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

    func restoreOffset(to pageFrame: CGRect, intraPageProgress: Double) -> Bool {
        guard let scrollView else { return false }

        let desiredY = scrollView.contentOffset.y
            + pageFrame.minY
            + (pageFrame.height * min(max(intraPageProgress, 0), 1))
            - referenceLineY
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let targetOffsetY = min(max(desiredY, minOffsetY), maxOffsetY)
        isRestoringOffset = true
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY), animated: false)
        isRestoringOffset = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1))
            self?.syncViewportMetrics()
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
            guard !self.isRestoringOffset else { return }
            self.lastMotionTime = CACurrentMediaTime()
            self.syncViewportMetrics()
        }
    }

    private func installBoundsObservationIfNeeded() {
        guard let scrollView else { return }
        boundsObservation = scrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
            self?.syncViewportMetrics()
        }
    }

    private func syncViewportMetrics() {
        let metrics: ReaderVerticalViewportMetrics
        guard let scrollView else {
            metrics = ReaderVerticalViewportMetrics()
            updateViewportMetrics(metrics)
            return
        }
        let contentOffsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        metrics = ReaderVerticalViewportMetrics(
            contentOffsetY: contentOffsetY,
            viewportHeight: scrollView.bounds.height
        )
        updateViewportMetrics(metrics)
    }

    private func updateViewportMetrics(_ metrics: ReaderVerticalViewportMetrics) {
        guard metrics != currentViewportMetrics else { return }
        currentViewportMetrics = metrics
        pendingViewportMetrics = metrics
        scheduleViewportMetricsPublication()
    }

    private func scheduleViewportMetricsPublication() {
        guard !isViewportMetricsPublicationScheduled else { return }
        isViewportMetricsPublicationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isViewportMetricsPublicationScheduled = false
            guard let metrics = self.pendingViewportMetrics else { return }
            self.pendingViewportMetrics = nil
            if metrics != self.viewportMetrics {
                self.viewportMetrics = metrics
            }
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
        return scrollView.isDragging || scrollView.isDecelerating
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
            guard let self, let scrollView = self.nearestAncestorScrollView() else { return }
            guard scrollView !== self.resolvedScrollView else { return }
            self.resolvedScrollView = scrollView
            self.onResolve?(scrollView)
        }
    }

    private func nearestAncestorScrollView() -> UIScrollView? {
        var candidate = superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
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
