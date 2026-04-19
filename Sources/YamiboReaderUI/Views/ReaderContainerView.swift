import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct ReaderContainerView: View {
    @StateObject private var model: ReaderContainerModel
    @State private var showingSettings = false
    @State private var showingCachePanel = false
    @State private var showingCacheProgress = false
    @State private var showingWebJumpSheet = false
    @State private var isChapterDrawerVisible = false
    @State private var isChromeVisible = true
    @State private var didEnterImmersiveMode = false
    @State private var verticalScrollRequest: Int?
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

                ReaderChapterDrawerOverlay(
                    model: model,
                    isPresented: $isChapterDrawerVisible,
                    onSelect: { chapter in
                        jumpToChapter(chapter)
                    }
                )
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isChromeVisible {
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
                if isChromeVisible {
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
                Task { await model.saveProgress() }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(model: model)
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
            .statusBar(hidden: !model.settings.showsSystemStatusBar || !isChromeVisible)
            .onChange(of: model.isLoading) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.errorMessage) { _, _ in
                updateChromeForContentState()
            }
            .onChange(of: model.pages.count) { _, _ in
                updateChromeForContentState()
            }
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
        isChromeVisible = true
        Task { await model.loadCurrent(forceRefresh: false) }
    }

    private func refreshReader() {
        isChromeVisible = true
        Task { await model.loadCurrent(forceRefresh: true) }
    }

    private func openInForum() {
        isChromeVisible = true
        Task { await model.saveProgress() }
        appModel.dismissReader(openThreadInForum: model.forumURL)
    }

    private func closeReader() {
        isChromeVisible = true
        Task { await model.saveProgress() }
        appModel.dismissReader()
    }

    private func toggleChrome() {
        guard !model.pages.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
        }
    }

    private func openChapterDrawer() {
        isChromeVisible = true
        withAnimation(.easeInOut(duration: 0.2)) {
            isChapterDrawerVisible = true
        }
    }

    private func openSettings() {
        isChromeVisible = true
        showingSettings = true
    }

    private func openCachePanel() {
        isChromeVisible = true
        if model.hasCacheOperationSession {
            model.showCacheProgressIfRunning()
            showingCacheProgress = true
        } else {
            showingCachePanel = true
        }
    }

    private func openWebJumpSheet() {
        isChromeVisible = true
        showingWebJumpSheet = true
    }

    private func updateChromeForContentState() {
        if model.isLoading && model.pages.isEmpty {
            isChromeVisible = true
            return
        }

        if model.errorMessage != nil && model.pages.isEmpty {
            isChromeVisible = true
            return
        }

        guard !model.pages.isEmpty else { return }

        if model.settings.readingMode == .vertical {
            verticalScrollRequest = model.currentPageIndex
        }

        if !didEnterImmersiveMode {
            didEnterImmersiveMode = true
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible = false
            }
        }
    }

    private func commitProgressSlider(_ value: Double) {
        if model.settings.readingMode == .vertical {
            let percent = min(max(value, 0), 100)
            let targetIndex = Int((percent / 100) * Double(max(model.renderedPageCount - 1, 0)))
            model.jumpToRenderedPage(targetIndex)
            verticalScrollRequest = model.currentPageIndex
            return
        }

        model.jumpToRenderedPage(Int(value.rounded()))
    }

    private func jumpAdjacentChapter(_ delta: Int) {
        model.jumpToAdjacentChapter(delta)
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
        isChromeVisible = true
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
