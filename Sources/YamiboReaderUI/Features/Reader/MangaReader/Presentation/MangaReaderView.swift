import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel
    @StateObject private var model: MangaReaderModel
    @State private var isDismissing = false
    @State private var isChromeVisible = true
    @State private var isDirectoryPresented = false
    @State private var isChapterCommentsPresented = false
    @State private var isSettingsPresented = false

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
        _model = StateObject(
            wrappedValue: MangaReaderModel(context: context, appContext: appModel.appContext)
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)

            MangaReaderPresentationContent(
                presentation: model.presentation,
                imagePipeline: model.imagePipeline,
                onCurrentPageChange: { globalIndex in
                    model.updateCurrentPage(globalIndex: globalIndex)
                },
                onTap: {
                    toggleChrome()
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                MangaReaderFloatingControls(
                    topInset: topInset,
                    bottomInset: bottomInset,
                    isVisible: isChromeVisible,
                    imagePipeline: model.imagePipeline,
                    summary: mangaChromeSummary(from: model.presentation),
                    onClose: closeReader,
                    onShowDirectory: {
                        isDirectoryPresented = true
                    },
                    onShowComments: {
                        isChapterCommentsPresented = true
                    },
                    onShowSettings: {
                        isSettingsPresented = true
                    },
                    onOpenOriginalPost: openOriginalPost,
                    onJumpToLocalPage: { targetIndex in
                        Task { await model.jumpToPage(localIndex: targetIndex) }
                    }
                )
            }
            .task {
                await model.prepare()
            }
            .onDisappear {
                Task {
                    await model.saveProgress()
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBar(hidden: !isChromeVisible)
        .sheet(isPresented: $isDirectoryPresented) {
            if case let .loaded(loaded) = model.presentation.state {
                MangaDirectorySheet(
                    panel: loaded.directoryPanel,
                    onSortOrderChange: { sortOrder in
                        var settings = model.presentation.settings
                        settings.directorySortOrder = sortOrder
                        model.applySettings(settings)
                    },
                    onUpdateDirectory: {
                        Task { await model.updateDirectoryFromPanel() }
                    },
                    onSaveCorrection: { draft in
                        Task { await model.renameDirectory(with: draft) }
                    },
                    onDeleteChapters: { selectedTIDs in
                        Task { await model.deleteDirectoryChapters(tids: selectedTIDs) }
                    },
                    onSelectChapter: { chapter in
                        isDirectoryPresented = false
                        Task { await model.jumpToChapter(chapter) }
                    }
                )
            } else {
                MangaDirectoryUnavailableSheet()
            }
        }
        .sheet(isPresented: $isChapterCommentsPresented) {
            MangaChapterCommentsSheet(
                model: model,
                target: model.currentChapterCommentTarget,
                appModel: appModel
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            MangaReaderSettingsSheet(model: model)
        }
    }

    private func toggleChrome() {
        guard canToggleChrome else { return }
        withAnimation(.easeInOut(duration: ReaderChromeVisibilityAnimationPresentation.fade.duration)) {
            isChromeVisible.toggle()
        }
    }

    private var canToggleChrome: Bool {
        guard case let .loaded(loaded) = model.presentation.state else { return false }
        return !loaded.pages.isEmpty
    }

    private func closeReader() {
        guard !isDismissing else { return }
        isDismissing = true
        Task {
            await model.saveProgress()
            appModel.dismissManga()
        }
    }

    private func openOriginalPost() {
        guard !isDismissing else { return }
        isDismissing = true
        Task {
            let latestRoute = await model.saveProgress()
            appModel.dismissManga(
                openThreadInForum: context.originalThreadURL,
                suspendedRoute: latestRoute
            )
        }
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private func mangaChromeSummary(from presentation: MangaReaderPresentation) -> MangaReaderChromeSummary? {
        guard case let .loaded(loaded) = presentation.state,
              !loaded.pages.isEmpty else {
            return nil
        }

        let pages = loaded.pages
        let currentPage = loaded.currentPage
            ?? loaded.currentPageIndex.flatMap { pages.indices.contains($0) ? pages[$0] : nil }
            ?? pages[0]
        let itemCount = max(currentPage.chapterPageCount, 1)
        let maxIndex = max(itemCount - 1, 1)
        let currentIndex = min(max(currentPage.localIndex, 0), itemCount - 1)
        let progressFraction = itemCount > 1 ? Double(currentIndex) / Double(maxIndex) : 0
        let percentText = "\(Int((progressFraction * 100).rounded()))%"
        let pageSummary = L10n.string("manga.preview_page", currentIndex + 1, itemCount)
        let rawTitle = loaded.directoryPanel.displayChapters
            .first { $0.tid == currentPage.tid }?
            .rawTitle ?? currentPage.chapterTitle
        let headerTitle = MangaChapterDisplayFormatter.readerHeaderTitle(
            rawTitle: rawTitle,
            cleanBookName: loaded.directoryTitle
        )
        let pagePreviewTargets = pages.reduce(into: [Int: MangaReaderPageProjection]()) { result, page in
            guard page.tid == currentPage.tid else { return }
            result[page.localIndex] = page
        }

        return MangaReaderChromeSummary(
            headerTitle: headerTitle,
            pageSummary: pageSummary,
            pagePreviewTargets: pagePreviewTargets,
            progress: ReaderChromeProgress(
                itemCount: itemCount,
                currentIndex: currentIndex,
                progressFraction: progressFraction,
                percentText: percentText,
                primaryText: L10n.string("manga.directory") + " · \(percentText)",
                secondaryText: pageSummary,
                ticks: [],
                scrubTargetIndexes: Array(0 ..< itemCount)
            )
        )
    }
}

private struct MangaReaderChromeSummary: Equatable, Sendable {
    let headerTitle: String
    let pageSummary: String
    let pagePreviewTargets: [Int: MangaReaderPageProjection]
    let progress: ReaderChromeProgress
}

private struct MangaReaderFloatingControls: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isVisible: Bool
    let imagePipeline: MangaImagePipeline?
    let summary: MangaReaderChromeSummary?
    let onClose: () -> Void
    let onShowDirectory: () -> Void
    let onShowComments: () -> Void
    let onShowSettings: () -> Void
    let onOpenOriginalPost: () -> Void
    let onJumpToLocalPage: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            if isVisible {
                MangaReaderTopChrome(
                    title: summary?.headerTitle,
                    topInset: topInset,
                    onClose: onClose
                )
                .transition(.opacity)
            }

            MangaReaderBottomControls(
                bottomInset: bottomInset,
                isVisible: isVisible,
                colorScheme: colorScheme,
                imagePipeline: imagePipeline,
                summary: summary,
                onShowDirectory: onShowDirectory,
                onShowComments: onShowComments,
                onShowSettings: onShowSettings,
                onOpenOriginalPost: onOpenOriginalPost,
                onJumpToLocalPage: onJumpToLocalPage
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MangaReaderTopChrome: View {
    let title: String?
    let topInset: CGFloat
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReaderGlassContainer(spacing: 12) {
            let closeButtonSize: CGFloat = 44

            ZStack {
                MangaReaderTopChapterTitle(title: title)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, closeButtonSize + 16)

                HStack {
                    Spacer(minLength: 0)
                    ReaderChromeCircleButton(
                        systemName: "xmark",
                        title: L10n.string("common.close"),
                        tint: readerChromeButtonTint(for: colorScheme),
                        action: onClose
                    )
                    .frame(width: closeButtonSize, height: closeButtonSize)
                }
            }
            .frame(maxWidth: .infinity, minHeight: closeButtonSize)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct MangaReaderTopChapterTitle: View {
    let title: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let title, !title.isEmpty {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MangaReaderBottomControls: View {
    let bottomInset: CGFloat
    let isVisible: Bool
    let colorScheme: ColorScheme
    let imagePipeline: MangaImagePipeline?
    let summary: MangaReaderChromeSummary?
    let onShowDirectory: () -> Void
    let onShowComments: () -> Void
    let onShowSettings: () -> Void
    let onOpenOriginalPost: () -> Void
    let onJumpToLocalPage: (Int) -> Void

    @State private var activeVerticalProgressPreview: ReaderProgressScrubPreview?

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let controlVisibility = ReaderBottomActionRowPresentation(isScrubbing: activeVerticalProgressPreview != nil)

        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: layout.verticalScrubberSideSpacing) {
                Spacer(minLength: 0)
                VStack(spacing: layout.panelSpacing) {
                    if let progress = summary?.progress {
                        MangaReaderDirectoryProgressControl(
                            progress: progress,
                            onShowDirectory: onShowDirectory
                        )
                    }

                    MangaReaderStaticActionControls(
                        colorScheme: colorScheme,
                        originalPostTitle: L10n.string("common.original_post"),
                        commentsTitle: L10n.string("reader.comments"),
                        settingsTitle: L10n.string("settings.title"),
                        bookmarkTitle: "书签",
                        cacheTitle: L10n.string("reader.cache"),
                        onOpenOriginalPost: onOpenOriginalPost,
                        onShowComments: onShowComments,
                        onShowSettings: onShowSettings
                    )
                }
                .frame(width: layout.maxChromeWidth)
                .opacity(controlVisibility.opacity)
                .allowsHitTesting(controlVisibility.allowsHitTesting)
                .accessibilityHidden(controlVisibility.isAccessibilityHidden)

                if let progress = summary?.progress {
                    MangaReaderVerticalProgressControl(
                        progress: progress,
                        onPreviewChange: { activeVerticalProgressPreview = $0 },
                        onJumpToLocalPage: onJumpToLocalPage
                    )
                }
            }
            .readerChromeAnchoredPopupVisibility(isVisible)

            if let pageSummary = summary?.pageSummary {
                MangaReaderBottomPageSummary(text: pageSummary)
                    .readerChromeFadeVisibility(isVisible)
            }
        }
        .padding(.top, layout.bottomChromeTopPadding)
        .padding(.horizontal, 12)
        .padding(.bottom, max(bottomInset - 18, 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .overlay {
            if let preview = activeVerticalProgressPreview {
                MangaReaderProgressImagePreview(
                    preview: preview,
                    page: summary?.pagePreviewTargets[preview.targetIndex],
                    imagePipeline: imagePipeline
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct MangaReaderBottomPageSummary: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .readerChromePanel(cornerRadius: 16, tint: readerChromePanelTint(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct MangaReaderDirectoryProgressControl: View {
    let progress: ReaderChromeProgress
    let onShowDirectory: () -> Void

    var body: some View {
        ReaderDirectoryProgressCapsule(
            title: progress.primaryText,
            progressFraction: progress.progressFraction,
            showsFill: false,
            supportsScrub: false,
            isScrubbing: false,
            ticks: progress.ticks,
            onTapDirectory: onShowDirectory,
            onScrub: { _, _ in },
            onEndScrub: {}
        )
    }
}

private struct MangaReaderVerticalProgressControl: View {
    let progress: ReaderChromeProgress
    let onPreviewChange: (ReaderProgressScrubPreview?) -> Void
    let onJumpToLocalPage: (Int) -> Void

    var body: some View {
        ReaderVerticalProgressCapsule(
            restingProgressFraction: progress.progressFraction,
            scrubContext: progress.scrubContext,
            ticks: progress.ticks,
            previewSize: MangaReaderProgressImagePreview.previewSize,
            showsPreview: false,
            onPreviewChange: onPreviewChange,
            onBeginScrub: {},
            onCommit: onJumpToLocalPage,
            onEndScrub: {
                onPreviewChange(nil)
            }
        ) { _ in
            EmptyView()
        }
        .frame(width: ReaderBottomChromeLayoutPresentation().verticalScrubberWidth, alignment: .trailing)
    }
}

private struct MangaReaderProgressImagePreview: View {
    static let previewSize = CGSize(width: 184, height: 228)

    let preview: ReaderProgressScrubPreview
    let page: MangaReaderPageProjection?
    let imagePipeline: MangaImagePipeline?

    @State private var loadedImage: UIImage?
    @State private var loadedPageID: String?
    @State private var loadingPageID: String?
    @State private var failedPageID: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pageID = page?.id

        VStack(spacing: 8) {
            MangaReaderProgressPreviewImageArea(
                image: displayedImage,
                isLoading: loadingPageID == pageID,
                hasFailed: page == nil || failedPageID == pageID
            )

            MangaReaderProgressPreviewPageLabel(
                text: L10n.string("reader.page_number_spaced", preview.pageNumber)
            )
        }
        .padding(8)
        .frame(width: Self.previewSize.width, height: Self.previewSize.height)
        .readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
        .task(id: pageID) { @MainActor in
            await loadImage()
        }
    }

    private var displayedImage: UIImage? {
        guard let page else { return nil }
        if let cachedImage = imagePipeline?.cachedImage(for: page) {
            return cachedImage
        }
        guard loadedPageID == page.id else { return nil }
        return loadedImage
    }

    @MainActor
    private func loadImage() async {
        guard let page, let imagePipeline else {
            loadedImage = nil
            loadedPageID = nil
            loadingPageID = nil
            failedPageID = nil
            return
        }

        if let cachedImage = imagePipeline.cachedImage(for: page) {
            loadedImage = cachedImage
            loadedPageID = page.id
            loadingPageID = nil
            failedPageID = nil
            return
        }

        loadingPageID = page.id
        failedPageID = nil

        do {
            let image = try await imagePipeline.image(for: page)
            guard !Task.isCancelled else { return }
            loadedImage = image
            loadedPageID = page.id
            loadingPageID = nil
            failedPageID = nil
        } catch {
            guard !Task.isCancelled else { return }
            if loadedPageID != page.id {
                loadedImage = nil
            }
            loadingPageID = nil
            failedPageID = page.id
        }
    }
}

private struct MangaReaderProgressPreviewImageArea: View {
    let image: UIImage?
    let isLoading: Bool
    let hasFailed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: hasFailed ? "exclamationmark.triangle" : "photo")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MangaReaderProgressPreviewPageLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
    }
}

private struct MangaReaderStaticActionControls: View {
    let colorScheme: ColorScheme
    let originalPostTitle: String
    let commentsTitle: String
    let settingsTitle: String
    let bookmarkTitle: String
    let cacheTitle: String
    let onOpenOriginalPost: () -> Void
    let onShowComments: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        ReaderChromeCapsuleButton(
            title: commentsTitle,
            systemName: "text.bubble",
            action: onShowComments
        )

        ReaderChromeCapsuleButton(
            title: settingsTitle,
            systemName: "gearshape",
            action: onShowSettings
        )

        HStack(spacing: 0) {
            bottomActionButton(
                title: originalPostTitle,
                systemName: "safari",
                handler: onOpenOriginalPost
            )
            Spacer(minLength: layout.actionButtonSpacing)
            bottomActionButton(
                title: bookmarkTitle,
                isEnabled: false,
                systemName: "bookmark",
                handler: {}
            )
            Spacer(minLength: layout.actionButtonSpacing)
            bottomActionButton(
                title: cacheTitle,
                isEnabled: false,
                systemName: "square.and.arrow.down",
                handler: {}
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.actionButtonRowHeight)
    }

    private func bottomActionButton(
        title: String,
        isEnabled: Bool = true,
        systemName: String,
        handler: @escaping () -> Void
    ) -> some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        return Button(action: handler) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: layout.actionButtonIconFrame, height: layout.actionButtonIconFrame)
        }
        .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
        .opacity(isEnabled ? 1 : 0.34)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

private struct MangaReaderPresentationContent: View {
    let presentation: MangaReaderPresentation
    let imagePipeline: MangaImagePipeline?
    let onCurrentPageChange: (Int) -> Void
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch presentation.state {
            case let .loading(loading):
                MangaReaderLoadingContent(title: loading.title)
            case let .loaded(loaded):
                MangaReaderLoadedContent(
                    loaded: loaded,
                    imagePipeline: imagePipeline,
                    onCurrentPageChange: onCurrentPageChange,
                    onTap: onTap
                )
            case let .failed(error):
                MangaReaderFailedContent(error: error)
            }

            brightnessOverlay(brightness: presentation.settings.brightness)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func brightnessOverlay(brightness: Double) -> some View {
        let delta = brightness - 1
        if delta < 0 {
            Color.black.opacity(min(0.7, abs(delta)))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else if delta > 0 {
            Color.white.opacity(min(0.18, delta * 0.18))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

private struct MangaReaderLoadingContent: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            MangaReaderTitleHeader(title: title)
            ProgressView(L10n.string("manga.loading"))
                .tint(.white)
        }
        .multilineTextAlignment(.center)
        .padding(16)
    }
}

private struct MangaReaderLoadedContent: View {
    let loaded: MangaReaderLoadedPresentation
    let imagePipeline: MangaImagePipeline?
    let onCurrentPageChange: (Int) -> Void
    let onTap: () -> Void

    var body: some View {
        if loaded.pages.isEmpty {
            MangaReaderEmptyContent()
        } else if let imagePipeline {
                MangaVerticalCollectionViewport(
                    pages: loaded.pages,
                    currentPageIndex: loaded.currentPageIndex,
                    viewportPlacement: loaded.viewportPlacement,
                    imagePipeline: imagePipeline,
                    onCurrentPageChange: onCurrentPageChange,
                    onTap: onTap
                )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView(L10n.string("manga.loading"))
                .tint(.white)
        }
    }
}

private struct MangaReaderFailedContent: View {
    let error: MangaReaderErrorPresentation

    var body: some View {
        VStack(spacing: 12) {
            Label(error.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(16)
    }
}

private struct MangaReaderTitleHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Label(L10n.string("manga.reader.title"), systemImage: "book.pages")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MangaReaderEmptyContent: View {
    var body: some View {
        VStack(spacing: 12) {
            Label(L10n.string("manga.no_chapters"), systemImage: "photo.on.rectangle")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}
#endif
