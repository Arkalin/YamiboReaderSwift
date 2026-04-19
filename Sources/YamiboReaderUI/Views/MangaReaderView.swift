import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct MangaReaderView: View {
    private static let verticalReaderCoordinateSpaceName = "MangaReaderVerticalCoordinateSpace"
    @StateObject private var model: MangaReaderModel
    @State private var showingSettings = false
    @State private var showingDirectorySheet = false
    @State private var showingChrome = true
    @State private var selectedPageID: MangaPage.ID?
    @State private var activeZoomPageID: MangaPage.ID?
    @State private var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    @State private var pagerRevision = UUID()
    @State private var sliderValue = 0.0
    @State private var isEditingSlider = false
    @State private var previewPageIndex: Int?
    @State private var isPreviewVisible = false
    @State private var previewHideTask: Task<Void, Never>?
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: MangaReaderModel(context: context, appContext: appModel.appContext))
        self.appModel = appModel
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)

            ZStack {
                Color.black.ignoresSafeArea()
                content(proxy: proxy)
                brightnessOverlay
                chapterTransitionOverlay

                if showingChrome, isPreviewVisible {
                    MangaChapterPreviewBubble(title: previewLabelText)
                        .padding(.bottom, bottomInset + 110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
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
            .onDisappear {
                previewHideTask?.cancel()
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
                MangaSettingsSheet(model: model)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDirectorySheet) {
                MangaDirectorySheet(model: model)
            }
            .onChange(of: model.currentPageIndex) { _, _ in
                syncSliderValueIfNeeded()
            }
            .onChange(of: model.isTransitioningChapter) { _, isTransitioning in
                if isTransitioning {
                    resetSliderPreview()
                } else {
                    syncSliderValueIfNeeded()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPreviewVisible)
            .statusBar(hidden: !model.settings.showsSystemStatusBar || !showingChrome)
        }
    }

    @ViewBuilder
    private func content(proxy: GeometryProxy) -> some View {
        if model.isLoading && model.pages.isEmpty {
            ProgressView("加载漫画中…")
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
                    Button("返回网页") {
                        appModel.fallbackMangaToWeb(
                            model.makeWebFallbackContext(
                                currentURL: model.context.chapterURL,
                                initialPage: model.context.initialPage
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                    Button("重试") {
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

    private var pagedContent: some View {
        TabView(selection: $selectedPageID) {
            ForEach(model.pages) { page in
                MangaPageContent(
                    page: page,
                    refererURL: page.chapterURL,
                    imageRepository: appModel.appContext.mangaImageRepository,
                    zoomEnabled: model.settings.zoomEnabled,
                    activeZoomPageID: $activeZoomPageID,
                    verticalZoomOverlay: $verticalZoomOverlay,
                    usesOverlayPresentation: false,
                    readerCoordinateSpaceName: nil,
                    showsChapterTitle: false,
                    onToggleChrome: { showingChrome.toggle() }
                )
                .tag(Optional(page.id))
                .padding(.vertical, 12)
            }
        }
        .allowsHitTesting(!model.isTransitioningChapter)
        .id(pagerRevision)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            activeZoomPageID = nil
            verticalZoomOverlay = nil
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
            model.updateCurrentPage(forPageID: newValue)
        }
        .onChange(of: model.viewportRequest) { _, newValue in
            guard let newValue else { return }
            activeZoomPageID = nil
            verticalZoomOverlay = nil
            applyViewportRequest(newValue)
        }
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
                                zoomEnabled: model.settings.zoomEnabled,
                                activeZoomPageID: $activeZoomPageID,
                                verticalZoomOverlay: $verticalZoomOverlay,
                                usesOverlayPresentation: true,
                                readerCoordinateSpaceName: Self.verticalReaderCoordinateSpaceName,
                                showsChapterTitle: false,
                                onToggleChrome: { showingChrome.toggle() }
                            )
                            .id(page.id)
                            .onAppear {
                                model.updateCurrentPage(forPageID: page.id)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .coordinateSpace(name: Self.verticalReaderCoordinateSpaceName)
                .scrollDisabled(activeZoomPageID != nil)

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
                proxy.scrollTo(request.targetPageID, anchor: .top)
            }
            .onChange(of: model.viewportRequest) { _, request in
                guard let request else { return }
                activeZoomPageID = nil
                verticalZoomOverlay = nil
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ReaderChromeIconButton(systemName: "xmark", title: "关闭") {
                    appModel.dismissMangaRestoringWebIfNeeded()
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    ReaderChromeIconButton(systemName: "safari", title: "原帖") {
                        appModel.dismissManga(openThreadInForum: model.context.originalThreadURL)
                    }
                    ReaderChromeIconButton(systemName: "arrow.clockwise", title: "刷新") {
                        Task { await model.retryCurrentChapter() }
                    }
                    .disabled(model.isTransitioningChapter)
                }
            }

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
        }
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
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
                    Text("章节加载中…")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("未缓存章节会先探测并尝试切换，失败时将自动回退网页模式。")
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
        guard isEditingSlider else { return }
        previewPageIndex = model.clampedLocalPageIndex(for: Int(sliderValue.rounded()))
        previewHideTask?.cancel()
        isPreviewVisible = true
    }

    private func handleSliderEditingChanged(_ editing: Bool) {
        isEditingSlider = editing
        previewHideTask?.cancel()

        if editing {
            sliderValue = clampedSliderValue(sliderValue)
            previewPageIndex = model.clampedLocalPageIndex(for: Int(sliderValue.rounded()))
            isPreviewVisible = true
            return
        }

        let targetIndex = model.clampedLocalPageIndex(for: Int(sliderValue.rounded()))
        model.requestCurrentChapterPage(targetIndex)
        schedulePreviewHide()
    }

    private func syncSliderValueIfNeeded() {
        guard !isEditingSlider else { return }
        sliderValue = Double(model.currentPage?.localIndex ?? 0)
    }

    private func schedulePreviewHide() {
        previewHideTask?.cancel()
        previewHideTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isPreviewVisible = false
                previewPageIndex = nil
            }
        }
    }

    private func resetSliderPreview() {
        previewHideTask?.cancel()
        isEditingSlider = false
        isPreviewVisible = false
        previewPageIndex = nil
        syncSliderValueIfNeeded()
    }

    private func clampedSliderValue(_ value: Double) -> Double {
        min(max(value, model.sliderRange.lowerBound), model.sliderRange.upperBound)
    }

    private var previewLabelText: String {
        model.previewLabel(forLocalIndex: previewPageIndex ?? model.currentPage?.localIndex ?? 0)
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}

private struct MangaSettingsSheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("阅读模式", selection: Binding(
                    get: { model.settings.readingMode },
                    set: {
                        var updated = model.settings
                        updated.readingMode = $0
                        model.applySettings(updated)
                    }
                )) {
                    ForEach(MangaReadingMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("启用缩放", isOn: Binding(
                    get: { model.settings.zoomEnabled },
                    set: {
                        var updated = model.settings
                        updated.zoomEnabled = $0
                        model.applySettings(updated)
                    }
                ))

                Toggle("显示系统状态栏", isOn: Binding(
                    get: { model.settings.showsSystemStatusBar },
                    set: {
                        var updated = model.settings
                        updated.showsSystemStatusBar = $0
                        model.applySettings(updated)
                    }
                ))

                VStack(alignment: .leading, spacing: 8) {
                    Text("亮度")
                    Slider(
                        value: Binding(
                            get: { model.settings.brightness },
                            set: {
                                var updated = model.settings
                                updated.brightness = $0
                                model.applySettings(updated)
                            }
                        ),
                        in: 0.25 ... 1.5
                    )
                }
            }
            .navigationTitle("漫画设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct MangaDirectorySheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle = ""
    @State private var editedPrimaryKeyword = ""
    @State private var editedSecondaryKeyword = ""
    @State private var isHeaderExpanded = false
    @State private var didLoadDraft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    chaptersSection
                    correctionSection
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                guard !didLoadDraft else { return }
                let draft = model.makeDirectoryEditDraft()
                editedTitle = draft.title
                editedPrimaryKeyword = draft.primaryKeyword
                editedSecondaryKeyword = draft.secondaryKeyword
                didLoadDraft = true
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.currentDirectoryTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(isHeaderExpanded ? nil : 1)
                .onTapGesture {
                    isHeaderExpanded.toggle()
                }

            HStack(spacing: 10) {
                ForEach(MangaDirectorySortOrder.allCases, id: \.self) { sortOrder in
                    Button(sortOrder.title) {
                        model.applyDirectorySortOrder(sortOrder)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.settings.directorySortOrder == sortOrder ? .accentColor : .gray.opacity(0.35))
                    .foregroundStyle(model.settings.directorySortOrder == sortOrder ? .white : .primary)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                if let latestChapterText = model.latestChapterText {
                    Text(latestChapterText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(model.directoryUpdateButtonTitle) {
                    Task { await model.updateDirectoryFromPanel() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isDirectoryUpdateSearchMode ? .indigo : .orange)
                .disabled(!model.isDirectoryUpdateButtonEnabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("章节列表")
                .font(.headline)

            if model.sortedDirectoryChapters.isEmpty {
                ContentUnavailableView("暂无章节", systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.sortedDirectoryChapters) { chapter in
                        MangaDirectoryChapterRow(
                            chapter: chapter,
                            isCurrent: chapter.tid == model.currentPage?.tid,
                            isDisabled: model.isTransitioningChapter
                        ) {
                            dismiss()
                            Task { await model.jumpToChapter(chapter) }
                        }
                    }
                }
            }
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("校正漫画信息")
                .font(.headline)

            TextField("漫画名称", text: $editedTitle)
                .textFieldStyle(.roundedBorder)

            TextField("关键词 1", text: $editedPrimaryKeyword)
                .textFieldStyle(.roundedBorder)

            TextField("关键词 2（可选）", text: $editedSecondaryKeyword)
                .textFieldStyle(.roundedBorder)

            Button("保存校正") {
                Task {
                    await model.renameDirectory(
                        cleanBookName: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchKeyword: combinedSearchKeyword
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var combinedSearchKeyword: String {
        [editedPrimaryKeyword, editedSecondaryKeyword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? .orange : .secondary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                TruncationAwareText(
                    chapter.rawTitle,
                    font: UIFont.preferredFont(forTextStyle: .subheadline),
                    lineLimit: isExpanded ? nil : 1,
                    isTruncated: $isTruncated
                )
                .font(.subheadline)
                .foregroundStyle(isCurrent ? .primary : .primary)

                if isTruncated {
                    Button(isExpanded ? "收起" : "展开") {
                        isExpanded.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if isCurrent {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.orange.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .opacity(isDisabled && !isCurrent ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent, !isDisabled else { return }
            onSelect()
        }
    }
}

private struct TruncationAwareText: View {
    let text: String
    let font: UIFont
    let lineLimit: Int?
    @Binding var isTruncated: Bool

    @State private var availableWidth: CGFloat = 0

    init(
        _ text: String,
        font: UIFont,
        lineLimit: Int?,
        isTruncated: Binding<Bool>
    ) {
        self.text = text
        self.font = font
        self.lineLimit = lineLimit
        _isTruncated = isTruncated
    }

    var body: some View {
        Text(text)
            .lineLimit(lineLimit)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            availableWidth = proxy.size.width
                            updateTruncation()
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            availableWidth = newValue
                            updateTruncation()
                        }
                }
            )
    }

    private func updateTruncation() {
        guard availableWidth > 0 else { return }
        let rect = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        .boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        isTruncated = rect.height > (font.lineHeight * 1.2)
    }
}

private struct MangaPageContent: View {
    let page: MangaPage
    let refererURL: URL
    let imageRepository: MangaImageRepository
    let zoomEnabled: Bool
    @Binding var activeZoomPageID: MangaPage.ID?
    @Binding var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    let usesOverlayPresentation: Bool
    let readerCoordinateSpaceName: String?
    let showsChapterTitle: Bool
    let onToggleChrome: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            MangaAuthenticatedImage(
                pageID: page.id,
                url: page.imageURL,
                refererURL: refererURL,
                imageRepository: imageRepository,
                zoomEnabled: zoomEnabled,
                activeZoomPageID: $activeZoomPageID,
                verticalZoomOverlay: $verticalZoomOverlay,
                usesOverlayPresentation: usesOverlayPresentation,
                readerCoordinateSpaceName: readerCoordinateSpaceName
            )
            if showsChapterTitle {
                Text(page.chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleChrome()
        }
    }
}

@MainActor
private final class MangaImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private let url: URL
    private let refererURL: URL
    private let imageRepository: MangaImageRepository
    private var didStart = false

    init(url: URL, refererURL: URL, imageRepository: MangaImageRepository) {
        self.url = url
        self.refererURL = refererURL
        self.imageRepository = imageRepository
    }

    func loadIfNeeded() async {
        guard !didStart, image == nil else { return }
        didStart = true

        do {
            let data = try await imageRepository.imageData(
                for: MangaImageRequest(
                    imageURL: url,
                    refererURL: refererURL
                )
            )
            guard let image = UIImage(data: data) else {
                didFail = true
                return
            }
            self.image = image
        } catch {
            didFail = true
        }
    }
}

private struct MangaAuthenticatedImage: View {
    @StateObject private var loader: MangaImageLoader
    let pageID: MangaPage.ID
    let zoomEnabled: Bool
    @Binding var activeZoomPageID: MangaPage.ID?
    @Binding var verticalZoomOverlay: MangaVerticalZoomOverlayState?
    let usesOverlayPresentation: Bool
    let readerCoordinateSpaceName: String?
    @State private var baseImageSize: CGSize = .zero
    @State private var imageFrameInReader: CGRect = .zero
    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    init(
        pageID: MangaPage.ID,
        url: URL,
        refererURL: URL,
        imageRepository: MangaImageRepository,
        zoomEnabled: Bool,
        activeZoomPageID: Binding<MangaPage.ID?>,
        verticalZoomOverlay: Binding<MangaVerticalZoomOverlayState?>,
        usesOverlayPresentation: Bool,
        readerCoordinateSpaceName: String?
    ) {
        self.pageID = pageID
        _loader = StateObject(
            wrappedValue: MangaImageLoader(
                url: url,
                refererURL: refererURL,
                imageRepository: imageRepository
            )
        )
        self.zoomEnabled = zoomEnabled
        _activeZoomPageID = activeZoomPageID
        _verticalZoomOverlay = verticalZoomOverlay
        self.usesOverlayPresentation = usesOverlayPresentation
        self.readerCoordinateSpaceName = readerCoordinateSpaceName
    }

    var body: some View {
        optionalDragGesture(
            Group {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: MangaImageBaseSizePreferenceKey.self, value: geometry.size)
                            }
                        )
                        .background(frameMeasurementOverlay)
                        .scaleEffect(inlineEffectiveScale)
                        .offset(
                            x: inlineOffset.width,
                            y: inlineOffset.height
                        )
                        .opacity(shouldHideInlineImage ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: inlineSteadyScale)
                        .animation(.easeOut(duration: 0.2), value: inlineSteadyOffset)
                } else if loader.didFail {
                    Label("图片加载失败", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                } else {
                    ProgressView()
                        .padding(.vertical, 40)
                }
            }
        )
        .frame(maxWidth: .infinity)
        .task { await loader.loadIfNeeded() }
        .onChange(of: pageID) { _, _ in
            resetInteractionState()
        }
        .onChange(of: zoomEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            resetInteractionState()
        }
        .onChange(of: activeZoomPageID) { _, newValue in
            guard let newValue, newValue != pageID else {
                if newValue == nil, usesOverlayPresentation {
                    verticalZoomOverlay = nil
                }
                return
            }
            guard steadyScale > 1.01 || (verticalZoomOverlay?.pageID == pageID) else { return }
            resetInteractionState()
        }
        .onPreferenceChange(MangaImageBaseSizePreferenceKey.self) { newValue in
            baseImageSize = newValue
            if usesOverlayPresentation {
                updateVerticalOverlayIfNeeded()
            } else {
                steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
                gestureOffset = .zero
            }
        }
        .simultaneousGesture(doubleTapGesture)
        .simultaneousGesture(magnifyGesture)
    }

    private var effectiveScale: CGFloat {
        steadyScale * gestureScale
    }

    private var inlineEffectiveScale: CGFloat {
        usesOverlayPresentation ? 1 : effectiveScale
    }

    private var inlineSteadyScale: CGFloat {
        usesOverlayPresentation ? 1 : steadyScale
    }

    private var inlineOffset: CGSize {
        usesOverlayPresentation ? .zero : CGSize(
            width: steadyOffset.width + gestureOffset.width,
            height: steadyOffset.height + gestureOffset.height
        )
    }

    private var inlineSteadyOffset: CGSize {
        usesOverlayPresentation ? .zero : steadyOffset
    }

    private var shouldHideInlineImage: Bool {
        usesOverlayPresentation && verticalZoomOverlay?.pageID == pageID
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard zoomEnabled else { return }
                if usesOverlayPresentation {
                    if verticalZoomOverlay?.pageID == pageID {
                        resetInteractionState()
                    } else {
                        guard canBeginZoom else { return }
                        activateVerticalOverlay(targetScale: 2)
                    }
                } else {
                    if steadyScale > 1.05 {
                        resetInteractionState()
                    } else {
                        guard canBeginZoom else { return }
                        steadyScale = 2
                        steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
                        gestureOffset = .zero
                        activeZoomPageID = pageID
                    }
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard canContinueMagnify else {
                    gestureScale = 1
                    return
                }
                if usesOverlayPresentation {
                    activateVerticalOverlayIfNeeded()
                    guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
                    overlay.gestureScale = value.magnification
                    verticalZoomOverlay = overlay
                } else {
                    gestureScale = value.magnification
                }
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard canContinueMagnify else {
                    gestureScale = 1
                    return
                }
                if usesOverlayPresentation {
                    activateVerticalOverlayIfNeeded()
                    guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
                    overlay.steadyScale = min(4, max(1, overlay.steadyScale * value.magnification))
                    overlay.gestureScale = 1
                    if overlay.steadyScale <= 1.01 {
                        resetInteractionState()
                    } else {
                        overlay.steadyOffset = clampedOffset(overlay.steadyOffset, scale: overlay.steadyScale)
                        overlay.gestureOffset = .zero
                        verticalZoomOverlay = overlay
                        activeZoomPageID = pageID
                    }
                } else {
                    steadyScale = min(4, max(1, steadyScale * value.magnification))
                    gestureScale = 1
                    if steadyScale <= 1.01 {
                        resetInteractionState()
                    } else {
                        steadyOffset = clampedOffset(steadyOffset, scale: steadyScale)
                        gestureOffset = .zero
                        activeZoomPageID = pageID
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                gestureOffset = clampedGestureTranslation(value.translation)
            }
            .onEnded { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                steadyOffset = clampedOffset(
                    CGSize(
                        width: steadyOffset.width + value.translation.width,
                        height: steadyOffset.height + value.translation.height
                    ),
                    scale: steadyScale
                )
                gestureOffset = .zero
                if steadyScale <= 1.05 {
                    steadyOffset = .zero
                }
            }
    }

    @ViewBuilder
    private func optionalDragGesture<Content: View>(_ content: Content) -> some View {
        if effectiveScale > 1.01 {
            content.simultaneousGesture(dragGesture)
        } else {
            content
        }
    }

    private func resetInteractionState() {
        baseImageSize = .zero
        imageFrameInReader = .zero
        steadyScale = 1
        gestureScale = 1
        steadyOffset = .zero
        gestureOffset = .zero
        if verticalZoomOverlay?.pageID == pageID {
            verticalZoomOverlay = nil
        }
        if activeZoomPageID == pageID {
            activeZoomPageID = nil
        }
    }

    private func clampedGestureTranslation(_ translation: CGSize) -> CGSize {
        let proposed = CGSize(
            width: steadyOffset.width + translation.width,
            height: steadyOffset.height + translation.height
        )
        let clamped = clampedOffset(proposed, scale: steadyScale)
        return CGSize(
            width: clamped.width - steadyOffset.width,
            height: clamped.height - steadyOffset.height
        )
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let bounds = dragBounds(for: scale)
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposed.width)),
            height: min(bounds.height, max(-bounds.height, proposed.height))
        )
    }

    private func dragBounds(for scale: CGFloat) -> CGSize {
        guard baseImageSize.width > 0, baseImageSize.height > 0 else {
            return .zero
        }

        return CGSize(
            width: max(0, (baseImageSize.width * scale - baseImageSize.width) / 2),
            height: max(0, (baseImageSize.height * scale - baseImageSize.height) / 2)
        )
    }

    private var canBeginZoom: Bool {
        activeZoomPageID == nil || activeZoomPageID == pageID
    }

    private var canContinueMagnify: Bool {
        if usesOverlayPresentation {
            return (verticalZoomOverlay?.pageID == pageID) || canBeginZoom
        }
        return steadyScale > 1.01 || canBeginZoom
    }

    @ViewBuilder
    private var frameMeasurementOverlay: some View {
        if let readerCoordinateSpaceName {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        imageFrameInReader = geometry.frame(in: .named(readerCoordinateSpaceName))
                        updateVerticalOverlayIfNeeded()
                    }
                    .onChange(of: geometry.frame(in: .named(readerCoordinateSpaceName))) { _, newValue in
                        imageFrameInReader = newValue
                        updateVerticalOverlayIfNeeded()
                    }
            }
        } else {
            Color.clear
        }
    }

    private func activateVerticalOverlay(targetScale: CGFloat) {
        guard let image = loader.image else { return }
        guard baseImageSize != .zero, imageFrameInReader != .zero else { return }
        activeZoomPageID = pageID
        verticalZoomOverlay = MangaVerticalZoomOverlayState(
            pageID: pageID,
            image: image,
            frame: imageFrameInReader,
            baseImageSize: baseImageSize,
            steadyScale: targetScale,
            gestureScale: 1,
            steadyOffset: .zero,
            gestureOffset: .zero
        )
    }

    private func activateVerticalOverlayIfNeeded() {
        guard usesOverlayPresentation else { return }
        if verticalZoomOverlay?.pageID != pageID {
            activateVerticalOverlay(targetScale: 1)
        }
    }

    private func updateVerticalOverlayIfNeeded() {
        guard usesOverlayPresentation else { return }
        guard var overlay = verticalZoomOverlay, overlay.pageID == pageID else { return }
        overlay.frame = imageFrameInReader
        overlay.baseImageSize = baseImageSize
        overlay.steadyOffset = clampedOffset(overlay.steadyOffset, scale: overlay.steadyScale)
        overlay.gestureOffset = .zero
        if let image = loader.image {
            overlay.image = image
        }
        verticalZoomOverlay = overlay
    }
}

private struct MangaImageBaseSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct MangaVerticalZoomOverlayState {
    let pageID: MangaPage.ID
    var image: UIImage
    var frame: CGRect
    var baseImageSize: CGSize
    var steadyScale: CGFloat
    var gestureScale: CGFloat
    var steadyOffset: CGSize
    var gestureOffset: CGSize
}

private struct MangaVerticalZoomOverlay: View {
    @Binding var overlay: MangaVerticalZoomOverlayState?
    @Binding var activeZoomPageID: MangaPage.ID?
    let zoomEnabled: Bool

    var body: some View {
        if let overlay {
            Image(uiImage: overlay.image)
                .resizable()
                .scaledToFit()
                .frame(width: overlay.baseImageSize.width, height: overlay.baseImageSize.height)
                .scaleEffect(overlay.steadyScale * overlay.gestureScale)
                .offset(
                    x: overlay.steadyOffset.width + overlay.gestureOffset.width,
                    y: overlay.steadyOffset.height + overlay.gestureOffset.height
                )
                .position(x: overlay.frame.midX, y: overlay.frame.midY)
                .animation(.easeOut(duration: 0.2), value: overlay.steadyScale)
                .animation(.easeOut(duration: 0.2), value: overlay.steadyOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(doubleTapGesture)
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard zoomEnabled else { return }
                reset()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                overlay.gestureScale = value.magnification
                self.overlay = overlay
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                overlay.steadyScale = min(4, max(1, overlay.steadyScale * value.magnification))
                overlay.gestureScale = 1
                if overlay.steadyScale <= 1.01 {
                    reset()
                } else {
                    overlay.steadyOffset = clampedOffset(overlay.steadyOffset, for: overlay)
                    overlay.gestureOffset = .zero
                    self.overlay = overlay
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                guard overlay.steadyScale > 1 else { return }
                overlay.gestureOffset = clampedGestureTranslation(value.translation, for: overlay)
                self.overlay = overlay
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                guard var overlay else { return }
                guard overlay.steadyScale > 1 else { return }
                overlay.steadyOffset = clampedOffset(
                    CGSize(
                        width: overlay.steadyOffset.width + value.translation.width,
                        height: overlay.steadyOffset.height + value.translation.height
                    ),
                    for: overlay
                )
                overlay.gestureOffset = .zero
                self.overlay = overlay
            }
    }

    private func reset() {
        overlay = nil
        activeZoomPageID = nil
    }

    private func clampedGestureTranslation(_ translation: CGSize, for overlay: MangaVerticalZoomOverlayState) -> CGSize {
        let proposed = CGSize(
            width: overlay.steadyOffset.width + translation.width,
            height: overlay.steadyOffset.height + translation.height
        )
        let clamped = clampedOffset(proposed, for: overlay)
        return CGSize(
            width: clamped.width - overlay.steadyOffset.width,
            height: clamped.height - overlay.steadyOffset.height
        )
    }

    private func clampedOffset(_ proposed: CGSize, for overlay: MangaVerticalZoomOverlayState) -> CGSize {
        let bounds = CGSize(
            width: max(0, (overlay.baseImageSize.width * overlay.steadyScale - overlay.baseImageSize.width) / 2),
            height: max(0, (overlay.baseImageSize.height * overlay.steadyScale - overlay.baseImageSize.height) / 2)
        )
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposed.width)),
            height: min(bounds.height, max(-bounds.height, proposed.height))
        )
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
        Text("漫画阅读仅在 iOS 端启用")
            .padding()
    }
}
#endif
