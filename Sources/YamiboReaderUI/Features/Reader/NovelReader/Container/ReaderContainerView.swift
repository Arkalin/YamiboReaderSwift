import SwiftUI
import YamiboReaderCore
import UIKit

public struct ReaderContainerView: View {
    @StateObject private var model: ReaderContainerModel
    @State private var verticalScrollCoordinator = ReaderVerticalScrollCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var showingCachePanel = false
    @State private var showingCacheProgress = false
    @State private var showingChapterSheet = false
    @State private var showingChapterComments = false
    @State private var imageBrowserItem: ReaderImageBrowserItem?
    @State private var chapterCommentsTarget: ReaderChapterCommentTarget?
    @State private var chromeState = ReaderChromeState()
    @State private var verticalScrollRequest: ReaderVerticalScrollRequest?
    @State private var verticalScrollRequestCommandID: UInt64 = 0
    @State private var verticalRestoreController = ReaderVerticalRestoreController()
    @State private var verticalRestoreRetryTask: Task<Void, Never>?
    @State private var verticalViewportPositionUpdateTask: Task<Void, Never>?
    @State private var verticalSurfaceFrames: [Int: ReaderVerticalSurfaceFrameValue] = [:]
    @State private var verticalTextViewportSample: NovelTextViewportSample?
    @State private var lastVerticalPositioningFingerprint: ReaderVerticalPositioningFingerprint?
    @State private var isVerticalProgressScrubbing = false
    @State private var verticalTapSuppressionUntil: CFTimeInterval = 0
    @State private var verticalBoundaryPullState = ReaderVerticalBoundaryPullState.idle
    @State private var isHandlingVerticalBoundaryPull = false
    @State private var isDismissing = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0
    @State private var pagedScrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    @State private var novelTextSelectionController = NovelTextSelectionController()
    private let appModel: YamiboAppModel

    public init(context: ReaderLaunchContext, appModel: YamiboAppModel) {
        let initialSettings = appModel.bootstrapState?.settings.reader
        _model = StateObject(wrappedValue: ReaderContainerModel(
            context: context,
            appContext: appModel.appContext,
            initialSettings: initialSettings,
            onReaderResumeRouteChange: { route in
                appModel.updateReaderResumeRoute(route)
            }
        ))
        _chromeState = State(initialValue: ReaderChromeState(
            showsChrome: initialSettings?.readingMode != .vertical
        ))
        self.appModel = appModel
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    public var body: some View {
        GeometryReader { proxy in
            let rawTopInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let topInset = effectiveTopInset(rawTopInset)
            let contentTopInset = model.settings.readingMode == .paged
                ? readerPagedContentTopInset(for: topInset)
                : readerContentTopInset(for: topInset, rawTopInset: rawTopInset)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)
            let currentLayout = readerLayout(
                proxy: proxy,
                topInset: topInset,
                bottomInset: bottomInset
            )
            let pagedPagerIdentity = ReaderPagedPagerIdentity(
                visibleView: model.visibleView,
                surfaceCount: model.readerSurfaces.count,
                spreadCount: model.presentationSpreads.count,
                usesTwoPageSpread: model.isTwoPageSpreadActive,
                layout: currentLayout
            )
            let loadingOverlayPresentation = readerLoadingOverlayPresentation

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                content(
                    topInset: contentTopInset,
                    bottomInset: bottomInset,
                    layout: currentLayout
                )
                .ignoresSafeArea(.container, edges: .top)
                .transaction { transaction in
                    if model.settings.readingMode == .paged {
                        transaction.animation = nil
                    }
                }
                .opacity(loadingOverlayPresentation.isPresented ? 0 : 1)

                ApplePencilPageTurnInteractionOverlay(
                    settings: model.applePencilPageTurnSettings,
                    canTurnPage: canReceiveApplePencilPageTurn
                ) { delta in
                    Task { await goRelativePage(delta, pagerIdentity: pagedPagerIdentity) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if loadingOverlayPresentation.allowsChrome {
                    if chromeState.showsChrome {
                        VStack(spacing: 0) {
                            topChrome(topInset: topInset)
                            Spacer(minLength: 0)
                        }
                        .transition(.opacity)
                        .zIndex(2)
                    }

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        bottomChrome(bottomInset: bottomInset, isVisible: chromeState.showsChrome)
                    }
                    .zIndex(2)

                }

                verticalBoundaryPullOverlayLayer(
                    topInset: topInset,
                    bottomInset: bottomInset
                )
                .zIndex(3)

                if loadingOverlayPresentation.isPresented {
                    readerLoadingOverlay
                        .zIndex(4)
                }
            }
            .disabled(hasPresentedOverlay)
            .allowsHitTesting(!hasPresentedOverlay)
            .modifier(readerLifecycleModifier(currentLayout: currentLayout))
            .modifier(readerPresentationModifier())
            .modifier(readerStateObserverModifier())
            .modifier(readerChromeHeightObserverModifier())
            .onChange(of: model.readerPresentation?.generation) { _, _ in
                novelTextSelectionController.clearSelection()
            }
            .onChange(of: model.settings.readingMode) { _, _ in
                novelTextSelectionController.clearSelection()
            }
        }
    }

    private func readerLifecycleModifier(currentLayout: ReaderContainerLayout) -> ReaderContainerLifecycleModifier {
        ReaderContainerLifecycleModifier(
            currentLayout: currentLayout,
            onInitialTask: {
                await model.commitNovelTextPresentationEnvironment(isPad: isPadDevice)
                await model.prepare(layout: currentLayout)
                updateChromeForContentState()
                restoreVerticalPositionIfNeeded()
            },
            onLayoutChange: { newValue in
                Task {
                    guard !hasPresentedOverlay else {
                        updateChromeForContentState()
                        return
                    }
                    await model.commitNovelTextLayout(newValue)
                    updateChromeForContentState()
                    restoreVerticalPositionIfNeeded()
                }
            },
            onMemoryWarning: {
                model.handleMemoryPressure()
            },
            onDisappear: {
                verticalRestoreRetryTask?.cancel()
                verticalViewportPositionUpdateTask?.cancel()
                syncVerticalViewportBeforeSave()
                Task {
                    await model.saveProgress()
                    model.close()
                }
            }
        )
    }

    private func readerPresentationModifier() -> ReaderContainerPresentationModifier {
        ReaderContainerPresentationModifier(
            model: model,
            showingSettings: $showingSettings,
            showingCachePanel: $showingCachePanel,
            showingCacheProgress: $showingCacheProgress,
            showingChapterSheet: $showingChapterSheet,
            showingChapterComments: $showingChapterComments,
            imageBrowserItem: $imageBrowserItem,
            chapterCommentsTarget: chapterCommentsTarget,
            onJumpToChapterDirectoryChapter: { chapter in
                Task { await jumpToChapterDirectoryChapter(chapter) }
            },
            onPreviewChapterDirectoryWebView: { view in
                Task { await model.previewChapterDirectoryWebView(view) }
            },
            onOpenOriginalPostFromComments: { url in
                openOriginalPostFromComments(url)
            }
        )
    }

    private func readerStateObserverModifier() -> ReaderContainerStateObserverModifier {
        ReaderContainerStateObserverModifier(
            model: model,
            showingSettings: $showingSettings,
            showingCachePanel: $showingCachePanel,
            showingCacheProgress: $showingCacheProgress,
            showingChapterSheet: $showingChapterSheet,
            showingChapterComments: $showingChapterComments,
            imageBrowserItem: $imageBrowserItem,
            isStatusBarHidden: chromeState.mode == .immersiveHidden,
            onUpdateChromeForContentState: {
                updateChromeForContentState()
            },
            onRestoreVerticalPositionIfNeeded: {
                restoreVerticalPositionIfNeeded()
            }
        )
    }

    private func readerChromeHeightObserverModifier() -> ReaderChromeHeightObserverModifier {
        ReaderChromeHeightObserverModifier(
            topChromeHeight: $topChromeHeight,
            bottomChromeHeight: $bottomChromeHeight
        )
    }

    @ViewBuilder
    private func content(topInset: CGFloat, bottomInset: CGFloat, layout: ReaderContainerLayout) -> some View {
        if let errorMessage = model.errorMessage, model.readerSurfaces.isEmpty {
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
            pagedContent(
                topInset: topInset,
                layout: layout
            )
        } else {
            verticalContent(
                topInset: topInset,
                bottomInset: bottomInset
            )
        }
    }

    private func pagedContent(topInset: CGFloat, layout: ReaderContainerLayout) -> some View {
        let pagerIdentity = ReaderPagedPagerIdentity(
            visibleView: model.visibleView,
            surfaceCount: model.readerSurfaces.count,
            spreadCount: model.presentationSpreads.count,
            usesTwoPageSpread: model.isTwoPageSpreadActive,
            layout: layout
        )
        let pagedTopInset = topInset + layout.chromeInsets.top
        return Group {
            if model.settings.pagedTurnStyle == .pageCurl {
                ReaderPagedPageCurlViewport(
                    spreads: model.presentationSpreads,
                    surfaces: model.readerSurfaces,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    imageDataLoader: model.inlineImageLoadingContext.loader,
                    imageCacheNamespace: model.inlineImageLoadingContext.cacheNamespace,
                    topInset: pagedTopInset,
                    bottomInset: layout.chromeInsets.bottom,
                    selectionIndex: model.pagedViewportSelectionIndex,
                    usesTwoPageSpread: model.isTwoPageSpreadActive,
                    pagerIdentity: pagerIdentity,
                    scrollAnimationRequest: pagedScrollAnimationRequest,
                    displayReferenceProvider: { surfaceIdentity in
                        model.novelTextViewportDisplayReference(for: surfaceIdentity)
                    },
                    selectionController: novelTextSelectionController,
                    isChromeVisible: chromeState.showsChrome,
                    canBoundaryPageTurn: { delta in
                        canNavigatePagedBoundary(delta: delta)
                    },
                    onSelectionChange: { selectionIndex in
                        model.selectPagedViewportIndex(selectionIndex)
                    },
                    onBoundaryPageTurn: { delta in
                        Task { await goRelativePage(delta, pagerIdentity: pagerIdentity) }
                    },
                    onPageTapZone: { zone in
                        handlePagedTapZone(zone, pagerIdentity: pagerIdentity)
                    },
                    onScrollAnimationRequestConsumed: { request in
                        clearPagedScrollAnimationRequest(request)
                    },
                    onChromeVisibleImageTap: {
                        enterImmersiveMode()
                    },
                    onImageTap: { url, title in
                        handleImageTap(url: url, title: title)
                    }
                )
            } else if model.isTwoPageSpreadActive {
                ReaderPresentationSpreadCollectionViewport(
                    spreads: model.presentationSpreads,
                    surfaces: model.readerSurfaces,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    imageDataLoader: model.inlineImageLoadingContext.loader,
                    imageCacheNamespace: model.inlineImageLoadingContext.cacheNamespace,
                    topInset: pagedTopInset,
                    bottomInset: layout.chromeInsets.bottom,
                    selectionIndex: model.pagedViewportSelectionIndex,
                    pagerIdentity: pagerIdentity,
                    scrollAnimationRequest: pagedScrollAnimationRequest,
                    displayReferenceProvider: { surfaceIdentity in
                        model.novelTextViewportDisplayReference(for: surfaceIdentity)
                    },
                    selectionController: novelTextSelectionController,
                    isChromeVisible: chromeState.showsChrome,
                    canBoundaryPageTurn: { delta in
                        canNavigatePagedBoundary(delta: delta)
                    },
                    onSelectionChange: { selectionIndex in
                        model.selectPagedViewportIndex(selectionIndex)
                    },
                    onBoundaryPageTurn: { delta in
                        Task { await goRelativePage(delta, pagerIdentity: pagerIdentity) }
                    },
                    onPageTapZone: { zone in
                        handlePagedTapZone(zone, pagerIdentity: pagerIdentity)
                    },
                    onScrollAnimationRequestConsumed: { request in
                        clearPagedScrollAnimationRequest(request)
                    },
                    onChromeVisibleImageTap: {
                        enterImmersiveMode()
                    },
                    onImageTap: { url, title in
                        handleImageTap(url: url, title: title)
                    }
                )
            } else {
                ReaderPagedCollectionViewport(
                    surfaces: model.readerSurfaces,
                    settings: model.settings,
                    refererURL: model.forumURL,
                    imageDataLoader: model.inlineImageLoadingContext.loader,
                    imageCacheNamespace: model.inlineImageLoadingContext.cacheNamespace,
                    topInset: pagedTopInset,
                    bottomInset: layout.chromeInsets.bottom,
                    selectionIndex: model.pagedViewportSelectionIndex,
                    pagerIdentity: pagerIdentity,
                    scrollAnimationRequest: pagedScrollAnimationRequest,
                    displayReferenceProvider: { surfaceIdentity in
                        model.novelTextViewportDisplayReference(for: surfaceIdentity)
                    },
                    selectionController: novelTextSelectionController,
                    isChromeVisible: chromeState.showsChrome,
                    canBoundaryPageTurn: { delta in
                        canNavigatePagedBoundary(delta: delta)
                    },
                    onSelectionChange: { selectionIndex in
                        model.selectPagedViewportIndex(selectionIndex)
                    },
                    onBoundaryPageTurn: { delta in
                        Task { await goRelativePage(delta, pagerIdentity: pagerIdentity) }
                    },
                    onPageTapZone: { zone in
                        handlePagedTapZone(zone, pagerIdentity: pagerIdentity)
                    },
                    onScrollAnimationRequestConsumed: { request in
                        clearPagedScrollAnimationRequest(request)
                    },
                    onChromeVisibleImageTap: {
                        enterImmersiveMode()
                    },
                    onImageTap: { url, title in
                        handleImageTap(url: url, title: title)
                    }
                )
            }
        }
        .id(pagerIdentity)
        .scrollDisabled(chromeState.showsChrome)
    }

    private func verticalContent(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ReaderVerticalViewportScrollView(
            surfaces: model.readerSurfaces,
            settings: model.settings,
            refererURL: model.forumURL,
            imageDataLoader: model.inlineImageLoadingContext.loader,
            imageCacheNamespace: model.inlineImageLoadingContext.cacheNamespace,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollRequest: verticalScrollRequest,
            displayReferenceProvider: { surfaceIdentity in
                model.novelTextViewportDisplayReference(for: surfaceIdentity)
            },
            selectionController: novelTextSelectionController,
            isChromeVisible: chromeState.showsChrome,
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
                if request.textAnchor != nil {
                    verticalRestoreController.beginSettling(request, now: CACurrentMediaTime())
                    verticalRestoreRetryTask?.cancel()
                    verticalRestoreRetryTask = nil
                    return
                }
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
                        applyVerticalViewportPositionUpdate(for: .viewportGeometryChanged)
                    }
                }
                verticalScrollCoordinator.onBoundaryPullStateChange = { state in
                    Task { @MainActor in
                        updateVerticalBoundaryPullState(state)
                    }
                }
            },
            onSurfaceFramesChange: { frames in
                guard verticalSurfaceFrames != frames else { return }
                verticalSurfaceFrames = frames
                tryAdvanceVerticalRestore()
                applyVerticalViewportPositionUpdate(for: .viewportGeometryChanged)
            },
            onTextViewportSampleChange: { sample in
                guard verticalTextViewportSample != sample else { return }
                verticalTextViewportSample = sample
                applyVerticalViewportPositionUpdate(for: .textViewportSampleChanged)
            },
            onViewportChange: {
                applyVerticalViewportPositionUpdate(for: .viewportGeometryChanged)
            },
            onScrollSettled: {
                updateVerticalViewportPosition()
            },
            onTap: {
                handleVerticalTap()
            },
            onChromeVisibleImageTap: {
                enterImmersiveMode()
            },
            onImageTap: { url, title in
                handleImageTap(url: url, title: title)
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(verticalScrollSuppressionGesture)
    }

    private var backgroundColor: Color {
        readerThemeColor(for: model.settings.backgroundStyle, colorScheme: colorScheme)
    }

    private var readerLoadingOverlayPresentation: ReaderLoadingOverlayPresentation {
        ReaderLoadingOverlayPresentation(
            isLoading: model.isLoading,
            hasSurfaces: !model.readerSurfaces.isEmpty,
            hasInitialLoadError: model.errorMessage != nil,
            isApplyingAppearanceSettings: model.isApplyingAppearanceSettings,
            isNavigatingReaderPageDocument: model.isNavigatingReaderPageDocument,
            shouldConcealViewportContent: verticalRestoreController.shouldConcealViewportContent
        )
    }

    private var readerLoadingOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay {
                ProgressView(L10n.string("common.loading"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        NovelReaderTopChrome(
            model: model,
            topInset: topInset,
            onNavigateBack: {
                Task { await navigateBackFromChrome() }
            },
            onNavigateForward: {
                Task { await navigateForwardFromChrome() }
            },
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
    private func bottomChrome(bottomInset: CGFloat, isVisible: Bool) -> some View {
        NovelReaderBottomChrome(
            progress: model.chromeProgressSnapshot.chromeProgress,
            readingMode: model.settings.readingMode,
            fillDirection: model.settings.pageTurnDirection.progressFillDirection,
            bottomInset: bottomInset,
            isVisible: isVisible,
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
            onVerticalProgressCommit: { surfaceIndex in
                commitVerticalProgressScrub(surfaceIndex)
            },
            onBeginVerticalProgressScrub: {
                beginVerticalProgressScrub()
            },
            onEndVerticalProgressScrub: {
                endVerticalProgressScrub()
            },
            isProgressScrubbing: isVerticalProgressScrubbing
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

    private func readerPagedContentTopInset(for layoutTopInset: CGFloat) -> CGFloat {
        layoutTopInset
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
        syncVerticalViewportBeforeSave()
        dismissReaderOpeningForum(model.currentForumTargetURL)
    }

    private func handleImageTap(url: URL, title: String?) {
        guard !chromeState.showsChrome else {
            enterImmersiveMode()
            return
        }
        openImageBrowser(url: url, title: title)
    }

    private func openImageBrowser(url: URL, title: String?) {
        imageBrowserItem = ReaderImageBrowserItem(
            url: url,
            title: imageBrowserTitle(title)
        )
    }

    private func imageBrowserTitle(_ title: String?) -> String {
        let candidates = [
            title,
            model.currentChapterTitle,
            model.title,
            L10n.string("reader.inline_images")
        ]
        return candidates.compactMap { candidate in
            let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalized.isEmpty ? nil : normalized
        }.first ?? L10n.string("reader.inline_images")
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

    private func openOriginalPostFromComments(_ url: URL) {
        dismissReaderOpeningForum(url)
    }

    private func dismissReaderOpeningForum(_ url: URL) {
        chromeState.showChrome()
        guard !isDismissing else { return }
        isDismissing = true
        syncVerticalViewportBeforeSave()
        Task {
            let resumeContext = await model.saveProgress()
            appModel.dismissReader(openThreadInForum: url, suspendedContext: resumeContext)
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

    private func handlePagedContentTap(
        pageDelta: Int? = nil,
        pagerIdentity: ReaderPagedPagerIdentity? = nil
    ) {
        guard !chromeState.showsChrome else {
            enterImmersiveMode()
            return
        }

        if let pageDelta {
            Task { await goRelativePage(pageDelta, pagerIdentity: pagerIdentity) }
        } else {
            toggleChrome()
        }
    }

    private func handlePagedTapZone(_ zone: ReaderPagedTapZone, pagerIdentity: ReaderPagedPagerIdentity) {
        switch zone {
        case .previous:
            handlePagedContentTap(pageDelta: -1, pagerIdentity: pagerIdentity)
        case .toggleChrome:
            handlePagedContentTap()
        case .next:
            handlePagedContentTap(pageDelta: 1, pagerIdentity: pagerIdentity)
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
            hasPresentedOverlay: hasChromePresentedOverlay,
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

        if currentVerticalPositioningFingerprint == nil {
            lastVerticalPositioningFingerprint = nil
        }
    }

    private var currentVerticalPositioningFingerprint: ReaderVerticalPositioningFingerprint? {
        guard model.settings.readingMode == .vertical,
              !model.readerSurfaces.isEmpty,
              let generation = model.readerPresentation?.generation else {
            return nil
        }
        return ReaderVerticalPositioningFingerprint(
            generation: generation,
            view: model.visibleView,
            surfaceCount: model.readerSurfaces.count,
            surfaceIndex: model.selectedSurfaceIndex,
            intraSurfaceProgressBucket: Int((model.currentSurfaceIntraProgress * 1000).rounded()),
            readingMode: model.settings.readingMode
        )
    }

    private func rememberCurrentVerticalPositioningFingerprint() {
        lastVerticalPositioningFingerprint = currentVerticalPositioningFingerprint
    }

    private func restoreVerticalPositionIfNeeded() {
        guard let fingerprint = currentVerticalPositioningFingerprint else {
            lastVerticalPositioningFingerprint = nil
            return
        }
        guard lastVerticalPositioningFingerprint != fingerprint else { return }
        lastVerticalPositioningFingerprint = fingerprint
        requestVerticalScrollToCurrentPage()
    }

    private func commitProgressSlider(_ targetIndex: Int) {
        model.jumpToSurface(targetIndex)
        restoreVerticalPositionIfNeeded()
    }

    private func jumpAdjacentChapter(_ delta: Int) {
        model.jumpToAdjacentChapter(delta)
        restoreVerticalPositionIfNeeded()
    }

    private func jumpToChapter(_ chapter: ReaderChapter) {
        model.jumpToChapter(chapter)
        restoreVerticalPositionIfNeeded()
    }

    private func jumpToChapterDirectoryChapter(_ chapter: ReaderChapter) async {
        await model.jumpToChapterDirectoryChapter(chapter)
        restoreVerticalPositionIfNeeded()
    }

    private func jumpToWebView(_ view: Int) async {
        await jumpToWebView(view, preferredSurfaceOrdinal: 0)
    }

    private func jumpToWebView(_ view: Int, preferredSurfaceOrdinal: Int) async {
        chromeState.showChrome()
        await model.jumpToWebView(view, preferredSurfaceOrdinal: preferredSurfaceOrdinal)
        restoreVerticalPositionIfNeeded()
    }

    private func navigateBackFromChrome() async {
        await model.navigateBack()
        restoreVerticalPositionIfNeeded()
    }

    private func navigateForwardFromChrome() async {
        await model.navigateForward()
        restoreVerticalPositionIfNeeded()
    }

    private func goRelativePage(_ delta: Int) async {
        pagedScrollAnimationRequest = nil
        await model.jumpRelativeSurface(delta)
        restoreVerticalPositionIfNeeded()
    }

    private func goRelativePage(_ delta: Int, pagerIdentity: ReaderPagedPagerIdentity?) async {
        let animationRequest = pagerIdentity.flatMap {
            makePagedScrollAnimationRequest(delta: delta, pagerIdentity: $0)
        }
        pagedScrollAnimationRequest = animationRequest
        await model.jumpRelativeSurface(delta)
        if let request = pagedScrollAnimationRequest,
           request.selectionIndex != model.pagedViewportSelectionIndex {
            pagedScrollAnimationRequest = nil
        }
        restoreVerticalPositionIfNeeded()
    }

    private func makePagedScrollAnimationRequest(
        delta: Int,
        pagerIdentity: ReaderPagedPagerIdentity
    ) -> ReaderPagedScrollAnimationRequest? {
        guard model.settings.readingMode == .paged else { return nil }
        let targetSelectionIndex = model.pagedViewportSelectionIndex + delta
        let selectionCount = model.isTwoPageSpreadActive
            ? model.presentationSpreads.count
            : model.readerSurfaces.count
        guard targetSelectionIndex >= 0, targetSelectionIndex < selectionCount else {
            return nil
        }
        return ReaderPagedScrollAnimationRequest(
            pagerIdentity: pagerIdentity,
            selectionIndex: targetSelectionIndex
        )
    }

    private func clearPagedScrollAnimationRequest(_ request: ReaderPagedScrollAnimationRequest) {
        guard pagedScrollAnimationRequest == request else { return }
        pagedScrollAnimationRequest = nil
    }

    private func canNavigatePagedBoundary(delta: Int) -> Bool {
        guard model.settings.readingMode == .paged, !model.readerSurfaces.isEmpty else { return false }
        if delta < 0 {
            return model.visibleView > 1
        }
        if delta > 0 {
            return model.visibleView < model.maxView
        }
        return false
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
        showingSettings ||
            showingCachePanel ||
            showingCacheProgress ||
            showingChapterSheet ||
            showingChapterComments ||
            imageBrowserItem != nil
    }

    private var hasChromePresentedOverlay: Bool {
        showingSettings ||
            showingCachePanel ||
            showingCacheProgress ||
            showingChapterSheet ||
            showingChapterComments
    }

    private var canReceiveApplePencilPageTurn: Bool {
        isPadDevice &&
            model.settings.readingMode == .paged &&
            !model.readerSurfaces.isEmpty &&
            !hasPresentedOverlay &&
            !isDismissing &&
            !chromeState.showsChrome
    }

    private func beginVerticalProgressScrub() {
        guard !isVerticalProgressScrubbing else { return }
        isVerticalProgressScrubbing = true
        verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
    }

    private func commitVerticalProgressScrub(_ target: Int) {
        model.jumpToSurface(target)
        restoreVerticalPositionIfNeeded()
        verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
    }

    private func endVerticalProgressScrub() {
        guard isVerticalProgressScrubbing else { return }
        isVerticalProgressScrubbing = false
        verticalTapSuppressionUntil = CACurrentMediaTime() + 0.5
    }

    private func makeVerticalScrollRequest() -> ReaderVerticalScrollRequest {
        let resumePoint = model.currentNovelResumePoint
        let textAnchor = resumePoint?.view == model.visibleView
            ? resumePoint.map(ReaderVerticalTextAnchor.init(position:))
            : nil
        verticalScrollRequestCommandID &+= 1
        let request = ReaderVerticalScrollRequest(
            commandID: verticalScrollRequestCommandID,
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
            rememberCurrentVerticalPositioningFingerprint()
        }
    }

    private func applyVerticalViewportPositionUpdate(for trigger: ReaderVerticalViewportPositionUpdateTiming.Trigger) {
        switch ReaderVerticalViewportPositionUpdateTiming.updateMode(for: trigger) {
        case .immediate:
            verticalViewportPositionUpdateTask?.cancel()
            verticalViewportPositionUpdateTask = nil
            updateVerticalViewportPosition()
        case .deferred:
            scheduleVerticalViewportPositionUpdate()
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
