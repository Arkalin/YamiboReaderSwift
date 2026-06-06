import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private struct ReaderVerticalViewportMetrics: Equatable {
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

private enum ReaderVerticalBoundaryDirection: Equatable {
    case previous
    case next
}

private struct ReaderVerticalBoundaryPullState: Equatable {
    var direction: ReaderVerticalBoundaryDirection?
    var distance: CGFloat = 0
    var isArmed = false

    static let idle = ReaderVerticalBoundaryPullState()
}

struct ReaderVerticalSurfaceFrameValue: Equatable {
    let documentView: Int
    let frame: CGRect
}

private struct ReaderVerticalPositioningFingerprint: Equatable {
    let view: Int
    let surfaceCount: Int
    let surfaceIndex: Int
    let intraSurfaceProgressBucket: Int
    let readingMode: ReaderReadingMode
}

private struct ReaderSurfaceSelectionTag: Hashable {
    let view: Int
    let index: Int
}

private let readerPadVisibleStatusBarTopInset: CGFloat = 32

private struct ReaderVerticalSurfaceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: ReaderVerticalSurfaceFrameValue] { [:] }

    static func reduce(value: inout [Int: ReaderVerticalSurfaceFrameValue], nextValue: () -> [Int: ReaderVerticalSurfaceFrameValue]) {
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

private struct ReaderVerticalBoundaryPullBadge: View {
    let text: String
    let systemImage: String
    let progress: CGFloat
    let isArmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReaderGlassContainer(spacing: 8) {
            Label {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: systemImage)
                    .symbolVariant(isArmed ? .fill : .none)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .readerChromePanel(cornerRadius: 22, tint: badgeTint)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.22 + 0.38 * progress), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 4)
        }
    }

    private var badgeTint: Color {
        if isArmed {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
        return readerChromePanelTint(for: colorScheme)
    }
}

public struct ReaderContainerView: View {
    @StateObject private var model: ReaderContainerModel
    @State private var verticalScrollCoordinator = ReaderVerticalScrollCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var showingCachePanel = false
    @State private var showingCacheProgress = false
    @State private var showingChapterSheet = false
    @State private var showingChapterComments = false
    @State private var chapterCommentsTarget: ReaderChapterCommentTarget?
    @State private var chromeState = ReaderChromeState()
    @State private var verticalScrollRequest: ReaderVerticalScrollRequest?
    @State private var verticalRestoreController = ReaderVerticalRestoreController()
    @State private var verticalRestoreRetryTask: Task<Void, Never>?
    @State private var verticalViewportPositionUpdateTask: Task<Void, Never>?
    @State private var verticalSurfaceFrames: [Int: ReaderVerticalSurfaceFrameValue] = [:]
    @State private var verticalTextViewportSample: NovelTextViewportSample?
    @State private var lastVerticalPositioningFingerprint: ReaderVerticalPositioningFingerprint?
    @State private var verticalProgressScrubState = ReaderProgressScrubState()
    @State private var verticalProgressStartFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @State private var verticalProgressTickFeedbackGenerator = UISelectionFeedbackGenerator()
    @State private var verticalProgressCommitFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @State private var verticalTapSuppressionUntil: CFTimeInterval = 0
    @State private var verticalBoundaryPullState = ReaderVerticalBoundaryPullState.idle
    @State private var isHandlingVerticalBoundaryPull = false
    @State private var isDismissing = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0
    private let appModel: YamiboAppModel

    public init(context: ReaderLaunchContext, appModel: YamiboAppModel) {
        let initialSettings = appModel.bootstrapState?.settings.reader
        _model = StateObject(wrappedValue: ReaderContainerModel(
            context: context,
            appContext: appModel.appContext,
            initialSettings: initialSettings
        ))
        _chromeState = State(initialValue: ReaderChromeState(
            showsChrome: initialSettings?.readingMode != .vertical
        ))
        self.appModel = appModel
    }

    private var isPadDevice: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    public var body: some View {
        GeometryReader { proxy in
            let rawTopInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let topInset = effectiveTopInset(rawTopInset)
            let contentTopInset = readerContentTopInset(for: topInset, rawTopInset: rawTopInset)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)
            let currentLayout = readerLayout(
                proxy: proxy,
                topInset: topInset,
                bottomInset: bottomInset
            )

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                content(
                    topInset: contentTopInset,
                    bottomInset: bottomInset,
                    layout: currentLayout
                )
                .ignoresSafeArea(.container, edges: .top)

                ApplePencilPageTurnInteractionOverlay(
                    settings: model.applePencilPageTurnSettings,
                    canTurnPage: canReceiveApplePencilPageTurn
                ) { delta in
                    Task { await goRelativePage(delta) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if chromeState.showsChrome {
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

                    verticalProgressScrubber(topInset: topInset, bottomInset: bottomInset)
                        .transition(.opacity)
                        .zIndex(2)
                }

                verticalBoundaryPullOverlayLayer(
                    topInset: topInset,
                    bottomInset: bottomInset
                )
                .zIndex(3)
            }
            .task {
                await model.commitNovelTextPresentationEnvironment(isPad: isPadDevice)
                await model.prepare(layout: currentLayout)
                updateChromeForContentState()
            }
            .onChange(of: currentLayout) { _, newValue in
                Task {
                    await model.commitNovelTextLayout(newValue)
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )) { _ in
                model.handleMemoryPressure()
            }
            .onDisappear {
                verticalRestoreRetryTask?.cancel()
                verticalViewportPositionUpdateTask?.cancel()
                syncVerticalViewportBeforeSave()
                Task {
                    await model.saveProgress()
                    model.close()
                }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showingChapterSheet) {
                ReaderChapterSheet(model: model) { chapter in
                    Task { await jumpToChapterDirectoryChapter(chapter) }
                } onSelectWebView: { view in
                    Task { await model.previewChapterDirectoryWebView(view) }
                }
            }
            .sheet(isPresented: $showingChapterComments) {
                ReaderChapterCommentsSheet(model: model, target: chapterCommentsTarget, appModel: appModel)
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
            .statusBar(hidden: chromeState.mode == .immersiveHidden)
            .onChange(of: model.isLoading) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.errorMessage) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.readerSurfaces.count) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.settings.readingMode) { _, _ in
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
            .onChange(of: showingChapterSheet) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: showingChapterComments) { _, _ in
                updateChromeForContentState()
            }
            .onPreferenceChange(ReaderTopChromeHeightPreferenceKey.self) { value in
                topChromeHeight = value
            }
            .onPreferenceChange(ReaderBottomChromeHeightPreferenceKey.self) { value in
                bottomChromeHeight = value
            }
        }
    }

    @ViewBuilder
    private func content(topInset: CGFloat, bottomInset: CGFloat, layout: ReaderContainerLayout) -> some View {
        if model.isLoading && model.readerSurfaces.isEmpty {
            VStack(spacing: 12) {
                ProgressView(L10n.string("common.loading"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage, model.readerSurfaces.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                Button(L10n.string("common.retry"), action: retryLoad)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.settings.readingMode == .paged {
            pagedContent(layout: layout)
        } else {
            verticalContent(
                topInset: topInset,
                bottomInset: bottomInset
            )
        }
    }

    private func pagedContent(layout: ReaderContainerLayout) -> some View {
        Group {
            if model.isTwoPageSpreadActive {
                ReaderPresentationSpreadCollectionViewport(
                    spreads: model.presentationSpreads,
                    surfaces: model.readerSurfaces,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    sessionState: model.sessionState,
                    topInset: layout.chromeInsets.top,
                    bottomInset: layout.chromeInsets.bottom,
                    selectionIndex: model.pagedViewportSelectionIndex,
                    displayReferenceProvider: { surfaceIdentity in
                        model.novelTextViewportDisplayReference(for: surfaceIdentity)
                    },
                    onSelectionChange: { selectionIndex in
                        model.selectPagedViewportIndex(selectionIndex)
                    }
                )
            } else {
                ReaderPagedCollectionViewport(
                    surfaces: model.readerSurfaces,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    sessionState: model.sessionState,
                    topInset: layout.chromeInsets.top,
                    bottomInset: layout.chromeInsets.bottom,
                    selectionIndex: model.pagedViewportSelectionIndex,
                    displayReferenceProvider: { surfaceIdentity in
                        model.novelTextViewportDisplayReference(for: surfaceIdentity)
                    },
                    onSelectionChange: { selectionIndex in
                        model.selectPagedViewportIndex(selectionIndex)
                    }
                )
            }
        }
        .id(
            ReaderPagedPagerIdentity(
                visibleView: model.visibleView,
                surfaceCount: model.readerSurfaces.count,
                spreadCount: model.presentationSpreads.count,
                usesTwoPageSpread: model.isTwoPageSpreadActive,
                layout: layout
            )
        )
        .scrollDisabled(chromeState.showsChrome)
        .overlay {
            if !model.readerSurfaces.isEmpty {
                ReaderPagedTapZones(
                    onPrevious: {
                        handlePagedContentTap(pageDelta: -1)
                    },
                    onToggleChrome: {
                        handlePagedContentTap()
                    },
                    onNext: {
                        handlePagedContentTap(pageDelta: 1)
                    }
                )
            }
        }
    }

    private func verticalContent(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            ReaderVerticalViewportScrollView(
                surfaces: model.readerSurfaces,
                settings: model.settings,
                refererURL: model.forumURL,
                sessionState: model.sessionState,
                topInset: topInset,
                bottomInset: bottomInset,
                scrollRequest: verticalScrollRequest,
                displayReferenceProvider: { surfaceIdentity in
                    model.novelTextViewportDisplayReference(for: surfaceIdentity)
                },
                onVisibleSurfaceIdentitiesChange: { surfaceIdentities in
                    model.updateNovelTextViewportVisibleSurfaceIdentities(surfaceIdentities)
                },
                onScrollRequestHandled: { request in
                    guard verticalRestoreController.scrollingRequest == request else {
                        if verticalScrollRequest == request {
                            verticalScrollRequest = nil
                        }
                        return
                    }
                    verticalScrollRequest = nil
                    tryAdvanceVerticalRestore()
                },
                onScrollViewReady: { scrollView in
                    verticalScrollCoordinator.attach(scrollView: scrollView)
                    verticalScrollCoordinator.onBoundaryPullRelease = { direction in
                        Task { @MainActor in
                            await handleVerticalBoundaryPullRelease(direction)
                        }
                    }
                    verticalScrollCoordinator.onViewportMetricsChange = {
                        Task { @MainActor in
                            tryAdvanceVerticalRestore()
                            scheduleVerticalViewportPositionUpdate()
                        }
                    }
                    verticalScrollCoordinator.onBoundaryPullStateChange = { state in
                        Task { @MainActor in
                            updateVerticalBoundaryPullState(state)
                        }
                    }
                },
                onSurfaceFramesChange: { frames in
                    verticalSurfaceFrames = frames
                    tryAdvanceVerticalRestore()
                    scheduleVerticalViewportPositionUpdate()
                },
                onTextViewportSampleChange: { sample in
                    verticalTextViewportSample = sample
                    scheduleVerticalViewportPositionUpdate()
                },
                onViewportChange: {
                    scheduleVerticalViewportPositionUpdate()
                },
                onScrollSettled: {
                    updateVerticalViewportPosition()
                },
                onTap: {
                    handleVerticalTap()
                }
            )
            .contentShape(Rectangle())
            .opacity(verticalRestoreController.shouldConcealViewportContent ? 0 : 1)
            .simultaneousGesture(verticalScrollSuppressionGesture)

            if verticalRestoreController.shouldConcealViewportContent {
                ProgressView(L10n.string("common.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var backgroundColor: Color {
        readerThemeColor(for: model.settings.backgroundStyle, colorScheme: colorScheme)
    }

    private func verticalBoundaryPullOverlayLayer(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            verticalBoundaryPullOverlay(
                direction: .previous,
                topInset: topInset,
                bottomInset: bottomInset
            )

            Spacer(minLength: 0)

            verticalBoundaryPullOverlay(
                direction: .next,
                topInset: topInset,
                bottomInset: bottomInset
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func verticalBoundaryPullOverlay(
        direction: ReaderVerticalBoundaryDirection,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        if verticalBoundaryPullState.direction == direction,
           canNavigateVerticalBoundary(direction) {
            let progress = min(max(verticalBoundaryPullState.distance / ReaderVerticalScrollCoordinator.boundaryTriggerDistance, 0), 1)
            ReaderVerticalBoundaryPullBadge(
                text: verticalBoundaryPullText(for: direction, isArmed: verticalBoundaryPullState.isArmed),
                systemImage: direction == .next ? "arrow.down.circle" : "arrow.up.circle",
                progress: progress,
                isArmed: verticalBoundaryPullState.isArmed
            )
            .padding(.top, direction == .previous ? verticalBoundaryPullTopPadding(topInset: topInset) : 0)
            .padding(.bottom, direction == .next ? verticalBoundaryPullBottomPadding(bottomInset: bottomInset) : 0)
            .opacity(0.45 + 0.55 * progress)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func verticalBoundaryPullTopPadding(topInset: CGFloat) -> CGFloat {
        let chromeAvoidance = chromeState.showsChrome ? max(topChromeHeight, topInset + 140) : 0
        return max(chromeAvoidance, topInset, 24) + 8
    }

    private func verticalBoundaryPullBottomPadding(bottomInset: CGFloat) -> CGFloat {
        let chromeAvoidance = chromeState.showsChrome ? max(bottomChromeHeight, bottomInset + 210) + 55 : 0
        return max(chromeAvoidance, bottomInset, 24) + 8
    }

    private func verticalBoundaryPullText(
        for direction: ReaderVerticalBoundaryDirection,
        isArmed: Bool
    ) -> String {
        switch (direction, isArmed) {
        case (.previous, false):
            return L10n.string("reader.pull_previous_web_page")
        case (.previous, true):
            return L10n.string("reader.release_previous_web_page")
        case (.next, false):
            return L10n.string("reader.pull_next_web_page")
        case (.next, true):
            return L10n.string("reader.release_next_web_page")
        }
    }

    @ViewBuilder
    private func topChrome(topInset: CGFloat) -> some View {
        ReaderTopChrome(
            model: model,
            topInset: topInset,
            onClose: closeReader,
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
            onShowSettings: openSettings,
            onShowCache: openCachePanel,
            onShowComments: openChapterComments,
            onOpenForum: openInForum,
            onJumpChapter: { delta in
                jumpAdjacentChapter(delta)
            },
            onProgressCommit: { surfaceIndex in
                commitProgressSlider(surfaceIndex)
            },
            isProgressScrubbing: verticalProgressScrubState.phase == .scrubbing
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

    @ViewBuilder
    private func verticalProgressScrubber(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let presentation = ReaderProgressChromePresentation(
            readingMode: model.settings.readingMode,
            isChromeVisible: chromeState.showsChrome
        )
        let layout = ReaderBottomChromeLayoutPresentation()
        if presentation.showsVerticalScrubber {
            ReaderVerticalProgressCapsule(
                progressFraction: verticalDisplayedProgressFraction,
                preview: verticalProgressScrubState.preview,
                isScrubbing: verticalProgressScrubState.phase == .scrubbing,
                ticks: model.progressChapterTicks,
                onScrub: { locationY, height in
                    handleVerticalProgressScrub(locationY: locationY, height: height)
                },
                onEndScrub: {
                    commitVerticalProgressScrub()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, max(bottomInset, 12) + layout.bottomControlsAdditionalBottomOffset + layout.verticalScrubberActionRowBottomOffset)
            .padding(.trailing, 12)
            .allowsHitTesting(true)
        }
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
        let chromeInsets = model.settings.readingMode == .paged
            ? ReaderLayoutInsets(top: 48)
            : .zero
        return ReaderContainerLayout(
            containerSize: proxy.size,
            safeAreaInsets: safeAreaInsets,
            contentInsets: contentInsets,
            chromeInsets: chromeInsets,
            readingMode: model.settings.readingMode
        )
    }

    private func effectiveTopInset(_ rawTopInset: CGFloat) -> CGFloat {
        // Keep pagination based on the status-bar-visible safe area so immersive status bar changes
        // do not move text or alter rendered page counts.
        guard isPadDevice else { return rawTopInset }
        return readerPadVisibleStatusBarTopInset
    }

    private func readerContentTopInset(for layoutTopInset: CGFloat, rawTopInset: CGFloat) -> CGFloat {
        guard isPadDevice else { return layoutTopInset }
        return rawTopInset > 0
            ? layoutTopInset
            : layoutTopInset + readerPadVisibleStatusBarTopInset
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
        guard !model.readerSurfaces.isEmpty else { return }
        guard !hasPresentedOverlay else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            chromeState.toggleChrome()
        }
    }

    private func enterImmersiveMode() {
        guard !model.readerSurfaces.isEmpty else { return }
        guard !hasPresentedOverlay else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            chromeState.hideChrome()
        }
    }

    private func handlePagedContentTap(pageDelta: Int? = nil) {
        guard !chromeState.showsChrome else {
            enterImmersiveMode()
            return
        }

        if let pageDelta {
            Task { await goRelativePage(pageDelta) }
        } else {
            toggleChrome()
        }
    }

    private func handleVerticalTap() {
        guard !model.readerSurfaces.isEmpty else { return }
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

    private func openChapterComments() {
        chapterCommentsTarget = model.currentChapterCommentTarget
        showingChapterComments = true
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

    private func updateChromeForContentState() {
        let previousState = chromeState
        var nextState = chromeState
        nextState.update(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            hasPages: !model.readerSurfaces.isEmpty,
            hasPresentedOverlay: hasPresentedOverlay,
            usesVerticalReadingMode: model.settings.readingMode == .vertical
        )
        if previousState != nextState {
            withAnimation(.easeInOut(duration: 0.2)) {
                chromeState = nextState
            }
        } else {
            chromeState = nextState
        }

        if model.isLoading && model.readerSurfaces.isEmpty {
            lastVerticalPositioningFingerprint = nil
            return
        }

        if model.errorMessage != nil && model.readerSurfaces.isEmpty {
            lastVerticalPositioningFingerprint = nil
            return
        }

        guard !model.readerSurfaces.isEmpty else {
            lastVerticalPositioningFingerprint = nil
            return
        }

        if model.settings.readingMode == .vertical {
            let fingerprint = ReaderVerticalPositioningFingerprint(
                view: model.visibleView,
                surfaceCount: model.readerSurfaces.count,
                surfaceIndex: model.selectedSurfaceIndex,
                intraSurfaceProgressBucket: Int((model.currentSurfaceIntraProgress * 1000).rounded()),
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

    private func commitProgressSlider(_ targetIndex: Int) {
        model.jumpToSurface(targetIndex)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func jumpAdjacentChapter(_ delta: Int) {
        model.jumpToAdjacentChapter(delta)
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

    private func jumpToChapterDirectoryChapter(_ chapter: ReaderChapter) async {
        await model.jumpToChapterDirectoryChapter(chapter)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func jumpToWebView(_ view: Int) async {
        await jumpToWebView(view, preferredSurfaceOrdinal: 0)
    }

    private func jumpToWebView(_ view: Int, preferredSurfaceOrdinal: Int) async {
        chromeState.showChrome()
        await model.jumpToWebView(view, preferredSurfaceOrdinal: preferredSurfaceOrdinal)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func goRelativePage(_ delta: Int) async {
        await model.jumpRelativeSurface(delta)
        if model.settings.readingMode == .vertical {
            requestVerticalScrollToCurrentPage()
        }
    }

    private func canNavigateVerticalBoundary(_ direction: ReaderVerticalBoundaryDirection) -> Bool {
        guard model.settings.readingMode == .vertical, !model.readerSurfaces.isEmpty else { return false }
        switch direction {
        case .previous:
            return model.visibleView > 1
        case .next:
            return model.visibleView < model.maxView
        }
    }

    private func updateVerticalBoundaryPullState(_ state: ReaderVerticalBoundaryPullState) {
        guard let direction = state.direction,
              canNavigateVerticalBoundary(direction) else {
            if verticalBoundaryPullState != .idle {
                withAnimation(.easeInOut(duration: 0.12)) {
                    verticalBoundaryPullState = .idle
                }
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            verticalBoundaryPullState = state
        }
    }

    private func handleVerticalBoundaryPullRelease(_ direction: ReaderVerticalBoundaryDirection) async {
        guard canNavigateVerticalBoundary(direction), !isHandlingVerticalBoundaryPull else { return }
        isHandlingVerticalBoundaryPull = true
        verticalBoundaryPullState = .idle
        cancelVerticalRestoreForUserScroll()
        switch direction {
        case .previous:
            await jumpToWebView(model.visibleView - 1, preferredSurfaceOrdinal: .max)
        case .next:
            await jumpToWebView(model.visibleView + 1, preferredSurfaceOrdinal: 0)
        }
        isHandlingVerticalBoundaryPull = false
    }

    private var hasPresentedOverlay: Bool {
        showingSettings || showingCachePanel || showingCacheProgress || showingChapterSheet || showingChapterComments
    }

    private var canReceiveApplePencilPageTurn: Bool {
        isPadDevice &&
            model.settings.readingMode == .paged &&
            !model.readerSurfaces.isEmpty &&
            !hasPresentedOverlay &&
            !isDismissing &&
            !chromeState.showsChrome
    }

    private var verticalProgressScrubContext: ReaderProgressScrubContext {
        ReaderProgressScrubContext(
            readingMode: .vertical,
            surfaceCount: model.surfaceCount,
            currentProgressPercent: model.currentProgressPercent,
            targetSurfaceIndex: { value in
                model.targetSurfaceIndex(forProgressValue: value)
            },
            chapterTitle: { surfaceIndex in
                model.chapterTitle(forSurfaceIndex: surfaceIndex)
            },
            chapterTickStartIndex: { surfaceIndex in
                model.progressChapterTickStartIndex(forSurfaceIndex: surfaceIndex)
            }
        )
    }

    private var verticalDisplayedProgressFraction: Double {
        if verticalProgressScrubState.phase == .scrubbing {
            guard model.surfaceCount > 1 else { return 0 }
            return Double(verticalProgressScrubState.targetSurfaceIndex) / Double(max(model.surfaceCount - 1, 1))
        }
        return model.currentProgressFraction
    }

    private func handleVerticalProgressScrub(locationY: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        let fraction = min(max(locationY / height, 0), 1)
        let value = fraction * 100
        let update = verticalProgressScrubState.update(value: value, context: verticalProgressScrubContext)
        triggerVerticalProgressFeedback(update.haptics)
        verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
    }

    private func commitVerticalProgressScrub() {
        guard verticalProgressScrubState.phase == .scrubbing else { return }
        let update = verticalProgressScrubState.end()
        triggerVerticalProgressFeedback(update.haptics)
        if let target = update.committedSurfaceIndex {
            model.jumpToSurface(target)
            requestVerticalScrollToCurrentPage()
        }
        verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
    }

    private func triggerVerticalProgressFeedback(_ haptics: [ReaderProgressScrubHaptic]) {
        for haptic in haptics {
            switch haptic {
            case .start:
                verticalProgressStartFeedbackGenerator.impactOccurred()
                verticalProgressStartFeedbackGenerator.prepare()
                verticalProgressTickFeedbackGenerator.prepare()
            case .chapterTick:
                verticalProgressTickFeedbackGenerator.selectionChanged()
                verticalProgressTickFeedbackGenerator.prepare()
            case .commit:
                verticalProgressCommitFeedbackGenerator.impactOccurred()
                verticalProgressCommitFeedbackGenerator.prepare()
            }
        }
    }

    private func makeVerticalScrollRequest() -> ReaderVerticalScrollRequest {
        let resumePoint = model.currentNovelResumePoint
        let textAnchor = resumePoint?.view == model.visibleView
            ? resumePoint.map(ReaderVerticalTextAnchor.init(position:))
            : nil
        let request = ReaderVerticalScrollRequest(
            view: model.visibleView,
            surfaceIndex: model.selectedSurfaceIndex,
            intraSurfaceProgress: model.currentSurfaceIntraProgress,
            textAnchor: textAnchor
        )
        return request
    }

    private func requestVerticalScrollToCurrentPage() {
        let request = makeVerticalScrollRequest()
        beginVerticalRestoreScrolling(for: request)
        verticalScrollRequest = request
        scheduleVerticalRestoreRetry(for: request)
    }

    private func updateVerticalViewportPosition() {
        guard model.settings.readingMode == .vertical else { return }
        guard verticalRestoreController.canSampleViewport(now: CACurrentMediaTime()) else {
            return
        }

        if let sample = verticalTextViewportSample {
            model.updateVerticalViewportPosition(sample: sample)
        }
    }

    private func scheduleVerticalViewportPositionUpdate() {
        verticalViewportPositionUpdateTask?.cancel()
        verticalViewportPositionUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                updateVerticalViewportPosition()
                verticalViewportPositionUpdateTask = nil
            }
        }
    }

    private func applyVerticalFineTune(for request: ReaderVerticalScrollRequest) {
        guard verticalRestoreController.scrollingRequest == request else {
            return
        }
        guard request.view == nil || request.view == model.visibleView else {
            return
        }
        if request.textAnchor != nil {
            verticalRestoreController.beginSettling(request, now: CACurrentMediaTime())
            verticalRestoreRetryTask?.cancel()
            verticalRestoreRetryTask = nil
            return
        }
        guard let frame = currentVerticalSurfaceFrames[request.surfaceIndex] else {
            return
        }
        verticalRestoreController.beginFineTuning(request)
        guard verticalScrollCoordinator.restoreOffset(
            to: frame,
            intraSurfaceProgress: request.intraSurfaceProgress
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
        guard request.view == nil || request.view == model.visibleView else {
            return
        }
        guard verticalScrollCoordinator.hasAttachedScrollView else {
            return
        }
        let frames = currentVerticalSurfaceFrames
        guard let frame = frames[request.surfaceIndex] else {
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
        updateVerticalViewportPosition()
    }

    private func beginVerticalRestoreScrolling(for request: ReaderVerticalScrollRequest) {
        verticalRestoreController.beginScrolling(to: request)
    }

    private var currentVerticalSurfaceFrames: [Int: CGRect] {
        verticalSurfaceFrames.compactMapValues { value in
            value.documentView == model.visibleView ? value.frame : nil
        }
    }

    private func refreshVerticalRestorePhase(now: CFTimeInterval = CACurrentMediaTime()) {
        verticalRestoreController.refresh(now: now)
    }

    private func cancelVerticalRestoreForUserScroll() {
        guard verticalRestoreController.activeRequest != nil else { return }
        verticalRestoreController.cancel(now: CACurrentMediaTime())
        verticalScrollRequest = nil
        verticalRestoreRetryTask?.cancel()
        verticalRestoreRetryTask = nil
    }

    private func reissueVerticalScrollRequest(_ request: ReaderVerticalScrollRequest) {
        guard verticalRestoreController.scrollingRequest == request else { return }
        verticalScrollRequest = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            guard verticalRestoreController.scrollingRequest == request else { return }
            verticalScrollRequest = request
        }
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
                        reissueVerticalScrollRequest(request)
                    }
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

private final class ReaderVerticalScrollCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let boundaryTriggerDistance: CGFloat = 72

    var onBoundaryPullRelease: ((ReaderVerticalBoundaryDirection) -> Void)?
    var onViewportMetricsChange: (() -> Void)?
    var onBoundaryPullStateChange: ((ReaderVerticalBoundaryPullState) -> Void)?

    private weak var scrollView: UIScrollView?
    private weak var interruptionTapRecognizer: UITapGestureRecognizer?
    private weak var boundaryPanGestureRecognizer: UIPanGestureRecognizer?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var currentViewportMetrics = ReaderVerticalViewportMetrics()
    private var pendingViewportMetrics: ReaderVerticalViewportMetrics?
    private var isViewportMetricsPublicationScheduled = false
    private var currentBoundaryPullState = ReaderVerticalBoundaryPullState.idle
    private var pendingBoundaryPullState: ReaderVerticalBoundaryPullState?
    private var isBoundaryPullStatePublicationScheduled = false
    private var isViewportSyncScheduled = false
    private var suppressChromeToggleUntil = CACurrentMediaTime()
    private var lastMotionTime = CACurrentMediaTime()
    private var isRestoringOffset = false
    private let motionSuppressionInterval: CFTimeInterval = 0.35

    func attach(scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        detachTapRecognizer()
        detachBoundaryPanTarget()
        contentOffsetObservation = nil
        boundsObservation = nil
        self.scrollView = scrollView
        scrollView?.alwaysBounceVertical = true
        installTapRecognizerIfNeeded()
        installBoundaryPanTargetIfNeeded()
        installContentOffsetObservationIfNeeded()
        installBoundsObservationIfNeeded()
        scheduleViewportSync()
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

    func restoreOffset(to surfaceFrame: CGRect, intraSurfaceProgress: Double) -> Bool {
        guard let scrollView else { return false }

        let desiredY = scrollView.contentOffset.y
            + surfaceFrame.minY
            + (surfaceFrame.height * min(max(intraSurfaceProgress, 0), 1))
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
            self?.scheduleViewportSync()
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
            self.scheduleViewportSync()
        }
    }

    private func installBoundsObservationIfNeeded() {
        guard let scrollView else { return }
        boundsObservation = scrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
            self?.scheduleViewportSync()
        }
    }

    private func scheduleViewportSync() {
        guard !isViewportSyncScheduled else { return }
        isViewportSyncScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            guard let self else { return }
            self.isViewportSyncScheduled = false
            self.syncViewportMetrics()
        }
    }

    private func syncViewportMetrics() {
        let metrics: ReaderVerticalViewportMetrics
        guard let scrollView else {
            metrics = ReaderVerticalViewportMetrics()
            updateViewportMetrics(metrics)
            updateBoundaryPullState(.idle)
            return
        }
        let contentOffsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        metrics = ReaderVerticalViewportMetrics(
            contentOffsetY: contentOffsetY,
            viewportHeight: scrollView.bounds.height
        )
        updateViewportMetrics(metrics)
        updateBoundaryPullState(boundaryPullState(for: scrollView))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            guard let self else { return }
            self.isViewportMetricsPublicationScheduled = false
            guard let metrics = self.pendingViewportMetrics else { return }
            self.pendingViewportMetrics = nil
            guard metrics == self.currentViewportMetrics else { return }
            self.onViewportMetricsChange?()
        }
    }

    private func boundaryPullState(for scrollView: UIScrollView) -> ReaderVerticalBoundaryPullState {
        guard let panGestureRecognizer = boundaryPanGestureRecognizer,
              scrollView.isDragging,
              panGestureRecognizer.state == .began || panGestureRecognizer.state == .changed else {
            return .idle
        }

        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let topOverscroll = max(minOffsetY - scrollView.contentOffset.y, 0)
        let bottomOverscroll = max(scrollView.contentOffset.y - maxOffsetY, 0)
        let translationY = panGestureRecognizer.translation(in: scrollView).y

        if topOverscroll > 0, translationY > 0 {
            return ReaderVerticalBoundaryPullState(
                direction: .previous,
                distance: topOverscroll,
                isArmed: topOverscroll >= Self.boundaryTriggerDistance
            )
        }

        if bottomOverscroll > 0, translationY < 0 {
            return ReaderVerticalBoundaryPullState(
                direction: .next,
                distance: bottomOverscroll,
                isArmed: bottomOverscroll >= Self.boundaryTriggerDistance
            )
        }

        return .idle
    }

    private func updateBoundaryPullState(_ state: ReaderVerticalBoundaryPullState) {
        if state == currentBoundaryPullState {
            pendingBoundaryPullState = nil
            return
        }
        guard state != pendingBoundaryPullState else {
            return
        }
        pendingBoundaryPullState = state
        scheduleBoundaryPullStatePublication()
    }

    private func scheduleBoundaryPullStatePublication() {
        guard !isBoundaryPullStatePublicationScheduled else { return }
        isBoundaryPullStatePublicationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            guard let self else { return }
            self.isBoundaryPullStatePublicationScheduled = false
            guard let state = self.pendingBoundaryPullState else { return }
            self.pendingBoundaryPullState = nil
            if state != self.currentBoundaryPullState {
                self.currentBoundaryPullState = state
                self.onBoundaryPullStateChange?(state)
            }
        }
    }

    private func detachTapRecognizer() {
        if let recognizer = interruptionTapRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        interruptionTapRecognizer = nil
    }

    private func installBoundaryPanTargetIfNeeded() {
        guard let panGestureRecognizer = scrollView?.panGestureRecognizer,
              boundaryPanGestureRecognizer !== panGestureRecognizer else {
            return
        }
        panGestureRecognizer.addTarget(self, action: #selector(handleBoundaryPan(_:)))
        boundaryPanGestureRecognizer = panGestureRecognizer
    }

    private func detachBoundaryPanTarget() {
        if let recognizer = boundaryPanGestureRecognizer {
            recognizer.removeTarget(self, action: #selector(handleBoundaryPan(_:)))
        }
        boundaryPanGestureRecognizer = nil
        updateBoundaryPullState(.idle)
    }

    @objc
    private func handleInterruptionTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard interruptScrollingIfNeeded() else { return }
        suppressChromeToggleUntil = CACurrentMediaTime() + motionSuppressionInterval
    }

    @objc
    private func handleBoundaryPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            let releasedState = currentBoundaryPullState
            updateBoundaryPullState(.idle)
            guard releasedState.isArmed,
                  let direction = releasedState.direction else {
                return
            }
            onBoundaryPullRelease?(direction)
        default:
            break
        }
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
            if let scrollView = current.firstDescendantScrollView(excluding: self) {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
    }
}

private extension UIView {
    func firstDescendantScrollView(excluding excludedView: UIView) -> UIScrollView? {
        for subview in subviews where subview !== excludedView {
            if let scrollView = subview as? UIScrollView {
                return scrollView
            }
            if let scrollView = subview.firstDescendantScrollView(excluding: excludedView) {
                return scrollView
            }
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
        Text(L10n.string("reader.ios_only"))
    }
}
#endif
