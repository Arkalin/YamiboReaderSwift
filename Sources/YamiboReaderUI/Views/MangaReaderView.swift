import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private struct MangaVerticalPageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MangaPage.ID: CGRect] { [:] }

    static func reduce(value: inout [MangaPage.ID: CGRect], nextValue: () -> [MangaPage.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MangaVerticalScrollRequest: Equatable, Sendable {
    let pageIndex: Int
    let intraPageProgress: Double
}

public struct MangaReaderView: View {
    private static let verticalReaderCoordinateSpaceName = "MangaReaderVerticalCoordinateSpace"
    private static let pagedTapDelayNanoseconds: UInt64 = 340_000_000
    private static let pagedDoubleTapMaximumDelay: TimeInterval = 0.36
    private static let pagedDoubleTapMaximumDistance: CGFloat = 48
    @StateObject private var model: MangaReaderModel
    @State private var showingSettings = false
    @State private var showingDirectorySheet = false
    @State private var showingChapterComments = false
    @State private var chapterCommentsTarget: ReaderChapterCommentTarget?
    @State private var showingChrome = true
    @State private var selectedPageID: MangaPage.ID?
    @State private var activeZoomPageID: MangaPage.ID?
    @State private var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    @State private var pagerRevision = UUID()
    @State private var sliderValue = 0.0
    @State private var isEditingSlider = false
    @State private var pendingPagedTapTask: Task<Void, Never>?
    @State private var pendingPagedTapToken = UUID()
    @State private var lastPagedTapDate: Date?
    @State private var lastPagedTapLocation: CGPoint?
    @State private var suppressPagedSingleTapUntil = Date.distantPast
    @State private var verticalRestoreController = VerticalRestoreController<MangaVerticalScrollRequest>()
    @State private var verticalRestoreSettleTask: Task<Void, Never>?
    @State private var verticalPageFrames: [MangaPage.ID: CGRect] = [:]
    @State private var isDismissing = false
    @Environment(\.colorScheme) private var colorScheme
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: MangaReaderModel(context: context, appContext: appModel.appContext))
        self.appModel = appModel
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)

            ZStack {
                Color.black.ignoresSafeArea()
                content(proxy: proxy)
                ApplePencilPageTurnInteractionOverlay(
                    settings: model.applePencilPageTurnSettings,
                    canTurnPage: canReceiveApplePencilPageTurn
                ) { delta in
                    Task { await goRelativePage(delta) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                brightnessOverlay
                chapterTransitionOverlay
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showingChrome {
                    topChrome(topInset: topInset)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showingChrome {
                    bottomChrome(bottomInset: bottomInset)
                }
            }
            .task {
                await model.prepare()
            }
            .onAppear {
                model.updatePagedPresentationEnvironment(isPad: isPadDevice, viewportSize: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                model.updatePagedPresentationEnvironment(isPad: isPadDevice, viewportSize: newSize)
            }
            .onDisappear {
                pendingPagedTapTask?.cancel()
                verticalRestoreSettleTask?.cancel()
                Task { await model.saveProgress() }
            }
            .onChange(of: model.navigationRequest) { _, newValue in
                if let newValue {
                    switch newValue {
                    case let .fallbackWeb(context):
                        appModel.fallbackMangaToWeb(context)
                    case let .reopenNative(context):
                        appModel.presentManga(context)
                    }
                    model.consumeNavigationRequest()
                }
            }
            .sheet(isPresented: $showingSettings) {
                MangaSettingsSheet(model: model, showsPadPagedOptions: isPadDevice)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDirectorySheet) {
                MangaDirectorySheet(model: model)
            }
            .sheet(isPresented: $showingChapterComments) {
                MangaChapterCommentsSheet(model: model, target: chapterCommentsTarget, appModel: appModel)
            }
            .onChange(of: model.currentPageIndex) { _, _ in
                handleCurrentPageChanged()
            }
            .onChange(of: model.isTransitioningChapter) { _, isTransitioning in
                if isTransitioning {
                    resetSliderPreview()
                } else {
                    syncSliderValueIfNeeded()
                }
            }
            .statusBar(hidden: !showingChrome)
        }
    }

    @ViewBuilder
    private func content(proxy: GeometryProxy) -> some View {
        if model.isLoading && model.pages.isEmpty {
            ProgressView(L10n.string("manga.loading"))
                .tint(.white)
        } else if let errorMessage = model.errorMessage, model.pages.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(errorMessage)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack {
                    Button(L10n.string("manga.return_to_web")) {
                        appModel.fallbackMangaToWeb(
                            model.makeWebFallbackContext(
                                currentURL: model.context.chapterURL,
                                initialPage: model.context.initialPage
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                    Button(L10n.string("common.retry")) {
                        Task { await model.retryCurrentChapter() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        } else if model.settings.readingMode == .paged {
            pagedContent
        } else {
            verticalContent
        }
    }

    @ViewBuilder
    private var pagedContent: some View {
        if model.isTwoPageSpreadActive {
            twoPagePagedContent
        } else {
            singlePagePagedContent
        }
    }

    private var singlePagePagedContent: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedPageID) {
                ForEach(model.pages) { page in
                    pagedPageContent(page: page)
                    .tag(Optional(page.id))
                    .padding(.vertical, 12)
                }
            }
            .allowsHitTesting(!model.isTransitioningChapter)
            .scrollDisabled(showingChrome || activeZoomPageID != nil)
            .id(pagerRevision)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(pagedSingleTapGesture(containerWidth: proxy.size.width))
            .simultaneousGesture(pagedDoubleTapCancellationGesture)
            .simultaneousGesture(contentInteractionGesture)
            .onAppear {
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                if let request = model.viewportRequest {
                    applyViewportRequest(request)
                } else {
                    selectedPageID = model.currentPage?.id
                }
            }
            .onChange(of: selectedPageID) { _, newValue in
                guard let newValue else { return }
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                model.updateCurrentPage(forPageID: newValue)
            }
            .onChange(of: model.viewportRequest) { _, newValue in
                guard let newValue else { return }
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                applyViewportRequest(newValue)
            }
        }
    }

    private var twoPagePagedContent: some View {
        GeometryReader { proxy in
            TabView(selection: pagedSelection) {
                ForEach(model.pagedSpreads) { spread in
                    HStack(spacing: 0) {
                        pagedSpreadColumn(pageIndex: spread.leftPageIndex)
                        pagedSpreadColumn(pageIndex: spread.rightPageIndex)
                    }
                    .tag(spread.index)
                    .padding(.vertical, 12)
                }
            }
            .allowsHitTesting(!model.isTransitioningChapter)
            .scrollDisabled(showingChrome || activeZoomPageID != nil)
            .id(pagerRevision)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(pagedSingleTapGesture(containerWidth: proxy.size.width))
            .simultaneousGesture(pagedDoubleTapCancellationGesture)
            .simultaneousGesture(contentInteractionGesture)
            .onAppear {
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                if let request = model.viewportRequest {
                    applyViewportRequest(request)
                }
            }
            .onChange(of: model.viewportRequest) { _, newValue in
                guard let newValue else { return }
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                applyViewportRequest(newValue)
            }
        }
    }

    private var pagedSelection: Binding<Int> {
        Binding(
            get: { model.pagedSelectionIndex },
            set: { selectionIndex in
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                cancelPendingPagedTap()
                model.updatePagedSelection(selectionIndex)
            }
        )
    }

    private func pagedPageContent(page: MangaPage) -> some View {
        MangaPageContent(
            page: page,
            refererURL: page.chapterURL,
            imageRepository: appModel.appContext.mangaImageRepository,
            zoomEnabled: model.settings.zoomEnabled && !showingChrome,
            activeZoomPageID: $activeZoomPageID,
            verticalZoomOverlay: $verticalZoomOverlay,
            usesOverlayPresentation: false,
            readerCoordinateSpaceName: nil,
            showsChapterTitle: false,
            onToggleChrome: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pagedSpreadColumn(pageIndex: Int?) -> some View {
        let isActiveZoomPage = pageIndex.flatMap { index in
            model.pages.indices.contains(index) ? model.pages[index].id : nil
        } == activeZoomPageID

        Group {
            if let pageIndex, model.pages.indices.contains(pageIndex) {
                pagedPageContent(page: model.pages[pageIndex])
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(isActiveZoomPage ? 1 : 0)
    }

    private var verticalContent: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 12) {
                        ForEach(model.pages) { page in
                            MangaPageContent(
                                page: page,
                                refererURL: page.chapterURL,
                                imageRepository: appModel.appContext.mangaImageRepository,
                                zoomEnabled: model.settings.zoomEnabled && !showingChrome,
                                activeZoomPageID: $activeZoomPageID,
                                verticalZoomOverlay: $verticalZoomOverlay,
                                usesOverlayPresentation: true,
                                readerCoordinateSpaceName: Self.verticalReaderCoordinateSpaceName,
                                showsChapterTitle: false,
                                onToggleChrome: handleReadingAreaTap
                            )
                            .id(page.id)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: MangaVerticalPageFramePreferenceKey.self,
                                        value: [page.id: geometry.frame(in: .named(Self.verticalReaderCoordinateSpaceName))]
                                    )
                                }
                            )
                            .onAppear {
                                handleVerticalPageAppear(page)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .coordinateSpace(name: Self.verticalReaderCoordinateSpaceName)
                .scrollDisabled(activeZoomPageID != nil)
                .simultaneousGesture(contentInteractionGesture)
                .onPreferenceChange(MangaVerticalPageFramePreferenceKey.self) { frames in
                    verticalPageFrames = frames
                    updateVerticalViewportPosition()
                }

                if let overlay = verticalZoomOverlay {
                    MangaVerticalZoomOverlay(
                        overlay: $verticalZoomOverlay,
                        activeZoomPageID: $activeZoomPageID,
                        zoomEnabled: model.settings.zoomEnabled
                    )
                    .zIndex(10)
                }
            }
            .onAppear {
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                guard let request = model.viewportRequest else { return }
                beginVerticalRestore(for: request)
                proxy.scrollTo(request.targetPageID, anchor: .top)
            }
            .onChange(of: model.viewportRequest) { _, request in
                guard let request else { return }
                activeZoomPageID = nil
                verticalZoomOverlay = nil
                beginVerticalRestore(for: request)
                if request.animated {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(request.targetPageID, anchor: .top)
                    }
                } else {
                    proxy.scrollTo(request.targetPageID, anchor: .top)
                }
            }
        }
        .allowsHitTesting(!model.isTransitioningChapter)
    }

    private func topChrome(topInset: CGFloat) -> some View {
        ReaderGlassContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: model.title, textStyle: .headline)
                        .frame(height: MarqueeText.preferredHeight(for: .headline))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(model.progressLabelText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .readerChromePanel(tint: readerChromePanelTint(for: colorScheme))

                HStack(spacing: 12) {
                    ReaderChromeIconButton(systemName: "chevron.backward", title: L10n.string("common.back")) {
                        guard !isDismissing else { return }
                        isDismissing = true
                        Task {
                            await model.saveProgress()
                            appModel.dismissMangaRestoringWebIfNeeded()
                        }
                    }
                    .disabled(isDismissing)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        ReaderChromeIconButton(systemName: "safari", title: L10n.string("common.original_post")) {
                            guard !isDismissing else { return }
                            isDismissing = true
                            Task {
                                await model.saveProgress()
                                appModel.dismissManga(openThreadInForum: model.context.originalThreadURL)
                            }
                        }
                        .disabled(isDismissing)
                        ReaderChromeIconButton(systemName: "arrow.clockwise", title: L10n.string("common.refresh")) {
                            Task { await model.retryCurrentChapter() }
                        }
                        .disabled(model.isTransitioningChapter || isDismissing)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func bottomChrome(bottomInset: CGFloat) -> some View {
        MangaBottomChrome(
            model: model,
            bottomInset: bottomInset,
            sliderValue: sliderValue,
            isEditingSlider: isEditingSlider,
            onSliderValueChange: handleSliderValueChange(_:),
            onSliderEditingChanged: handleSliderEditingChanged(_:),
            onShowSettings: { showingSettings = true },
            onShowDirectory: { showingDirectorySheet = true },
            onShowComments: {
                chapterCommentsTarget = model.currentChapterCommentTarget
                showingChapterComments = true
            },
            onJumpChapter: { delta in
                Task { await model.jumpToAdjacentChapter(delta) }
            }
        )
    }

    private var brightnessOverlay: some View {
        let delta = model.settings.brightness - 1
        return Group {
            if delta < 0 {
                Color.black.opacity(min(0.7, abs(delta)))
            } else if delta > 0 {
                Color.white.opacity(min(0.18, delta * 0.18))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var chapterTransitionOverlay: some View {
        if model.isTransitioningChapter {
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                    Text(L10n.string("manga.chapter_loading"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(L10n.string("manga.chapter_loading_hint"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(24)
            }
        }
    }

    private func applyViewportRequest(_ request: MangaViewportRequest) {
        pagerRevision = request.revision
        selectedPageID = request.targetPageID
        syncSliderValueIfNeeded()
    }

    private func handleSliderValueChange(_ value: Double) {
        sliderValue = clampedSliderValue(value)
    }

    private func handleSliderEditingChanged(_ editing: Bool) {
        isEditingSlider = editing

        if editing {
            sliderValue = clampedSliderValue(sliderValue)
            return
        }

        commitSliderSelection()
    }

    private func syncSliderValueIfNeeded() {
        guard !isEditingSlider else { return }
        sliderValue = Double(model.currentPage?.localIndex ?? 0)
    }

    private func handleCurrentPageChanged() {
        syncSliderValueIfNeeded()
    }

    private func resetSliderPreview() {
        isEditingSlider = false
        syncSliderValueIfNeeded()
    }

    private func commitSliderSelection() {
        let targetIndex = model.clampedLocalPageIndex(for: Int(sliderValue.rounded()))
        model.requestCurrentChapterPage(targetIndex)
    }

    private func cancelSliderInteractionForContentGesture() {
        guard isEditingSlider else { return }
        isEditingSlider = false
    }

    private func handleVerticalPageAppear(_ page: MangaPage) {
        refreshVerticalRestorePhase()
        guard let request = verticalRestoreController.activeRequest else { return }
        guard request.pageIndex == page.globalIndex else { return }
        beginVerticalRestoreSettling(for: request)

        model.updateCurrentPage(forPageID: page.id)
    }

    private func updateVerticalViewportPosition() {
        guard model.settings.readingMode == .vertical, !verticalPageFrames.isEmpty else { return }
        guard activeZoomPageID == nil else { return }
        guard verticalRestoreController.canSampleViewport(now: CACurrentMediaTime()) else { return }

        let referenceLineY = verticalViewportReferenceLineY
        guard let bestMatch = verticalPageFrames
            .filter({ $0.value.height > 0 })
            .min(by: { lhs, rhs in
                verticalPageDistance(from: referenceLineY, to: lhs.value) <
                    verticalPageDistance(from: referenceLineY, to: rhs.value)
            }) else {
            return
        }

        model.updateCurrentPage(forPageID: bestMatch.key)
    }

    private func clampedSliderValue(_ value: Double) -> Double {
        min(max(value, model.sliderRange.lowerBound), model.sliderRange.upperBound)
    }

    private func pagedSingleTapGesture(containerWidth: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                schedulePagedSingleTap(at: value.location, containerWidth: containerWidth)
            }
    }

    private var pagedDoubleTapCancellationGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { _ in
                cancelPendingPagedTap(suppressingSingleTap: true)
            }
    }

    private func schedulePagedSingleTap(at location: CGPoint, containerWidth: CGFloat) {
        guard !model.pages.isEmpty,
              !model.isTransitioningChapter,
              activeZoomPageID == nil else {
            return
        }
        guard !showingChrome else {
            handleReadingAreaTap()
            return
        }

        let now = Date()
        guard now >= suppressPagedSingleTapUntil else { return }

        if let lastPagedTapDate,
           let lastPagedTapLocation,
           now.timeIntervalSince(lastPagedTapDate) <= Self.pagedDoubleTapMaximumDelay,
           distance(from: lastPagedTapLocation, to: location) <= Self.pagedDoubleTapMaximumDistance {
            cancelPendingPagedTap(suppressingSingleTap: true)
            return
        }

        lastPagedTapDate = now
        lastPagedTapLocation = location
        pendingPagedTapTask?.cancel()

        let token = UUID()
        pendingPagedTapToken = token
        pendingPagedTapTask = Task {
            try? await Task.sleep(nanoseconds: Self.pagedTapDelayNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingPagedTapToken == token,
                      activeZoomPageID == nil,
                      Date() >= suppressPagedSingleTapUntil else {
                    return
                }
                performPagedSingleTap(at: location, containerWidth: containerWidth)
                pendingPagedTapTask = nil
                lastPagedTapDate = nil
                lastPagedTapLocation = nil
            }
        }
    }

    private func cancelPendingPagedTap(suppressingSingleTap: Bool = false) {
        pendingPagedTapTask?.cancel()
        pendingPagedTapTask = nil
        lastPagedTapDate = nil
        lastPagedTapLocation = nil
        if suppressingSingleTap {
            suppressPagedSingleTapUntil = Date().addingTimeInterval(Self.pagedDoubleTapMaximumDelay)
        }
    }

    private func performPagedSingleTap(at location: CGPoint, containerWidth: CGFloat) {
        guard containerWidth > 0 else { return }
        guard !showingChrome else {
            handleReadingAreaTap()
            return
        }

        let zoneWidth = containerWidth / 3

        if location.x < zoneWidth {
            Task { await goRelativePage(-1) }
        } else if location.x > zoneWidth * 2 {
            Task { await goRelativePage(1) }
        } else {
            showingChrome.toggle()
        }
    }

    private func handleReadingAreaTap() {
        if showingChrome {
            activeZoomPageID = nil
            verticalZoomOverlay = nil
            cancelPendingPagedTap()
            cancelSliderInteractionForContentGesture()
            showingChrome = false
        } else {
            showingChrome = true
        }
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func goRelativePage(_ delta: Int) async {
        cancelVerticalRestoreForUserInteraction()
        cancelSliderInteractionForContentGesture()
        cancelPendingPagedTap()
        await model.jumpRelativePage(delta)
    }

    private var canReceiveApplePencilPageTurn: Bool {
        isPadDevice &&
            model.settings.readingMode == .paged &&
            !model.pages.isEmpty &&
            !model.isTransitioningChapter &&
            !showingSettings &&
            !showingDirectorySheet &&
            !isDismissing &&
            !showingChrome &&
            activeZoomPageID == nil &&
            verticalZoomOverlay == nil
    }

    private var contentInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                cancelVerticalRestoreForUserInteraction()
                cancelSliderInteractionForContentGesture()
            }
    }

    private func beginVerticalRestore(for request: MangaViewportRequest) {
        verticalRestoreSettleTask?.cancel()
        verticalRestoreSettleTask = nil
        verticalRestoreController.beginScrolling(
            to: MangaVerticalScrollRequest(
                pageIndex: request.targetIndex,
                intraPageProgress: 0
            )
        )
    }

    private func beginVerticalRestoreSettling(for request: MangaVerticalScrollRequest) {
        verticalRestoreController.beginSettling(request, now: CACurrentMediaTime())
        verticalRestoreSettleTask?.cancel()
        verticalRestoreSettleTask = Task {
            try? await Task.sleep(for: .milliseconds(460))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                refreshVerticalRestorePhase()
                updateVerticalViewportPosition()
                verticalRestoreSettleTask = nil
            }
        }
    }

    private func refreshVerticalRestorePhase(now: CFTimeInterval = CACurrentMediaTime()) {
        verticalRestoreController.refresh(now: now)
    }

    private func cancelVerticalRestoreForUserInteraction() {
        guard verticalRestoreController.activeRequest != nil else { return }
        verticalRestoreController.cancel(now: CACurrentMediaTime())
        verticalRestoreSettleTask?.cancel()
        verticalRestoreSettleTask = nil
    }

    private var verticalViewportReferenceLineY: CGFloat {
        96
    }

    private func verticalPageDistance(from referenceLineY: CGFloat, to frame: CGRect) -> CGFloat {
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

#else

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        Text(L10n.string("manga.ios_only"))
            .padding()
    }
}
#endif
