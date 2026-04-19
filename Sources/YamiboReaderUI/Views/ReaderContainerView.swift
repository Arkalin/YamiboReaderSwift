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
            .simultaneousGesture(
                TapGesture().onEnded {
                    toggleChrome()
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
        if model.settings.usesNightMode {
            return Color(red: 0.1, green: 0.11, blue: 0.12)
        }
        switch model.settings.backgroundStyle {
        case .system:
            return Color(uiColor: .systemBackground)
        case .paper:
            return Color(red: 0.98, green: 0.95, blue: 0.88)
        case .mint:
            return Color(red: 0.91, green: 0.97, blue: 0.93)
        case .sakura:
            return Color(red: 0.98, green: 0.92, blue: 0.94)
        }
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
