import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel
    @StateObject private var model: MangaReaderModel
    @State private var isDismissing = false
    @State private var isDirectoryPresented = false
    @State private var isChapterCommentsPresented = false

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
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                MangaReaderFloatingControls(
                    topInset: topInset,
                    bottomInset: bottomInset,
                    progress: mangaChromeProgress(from: model.presentation),
                    onClose: closeReader,
                    onShowDirectory: {
                        isDirectoryPresented = true
                    },
                    onShowComments: {
                        isChapterCommentsPresented = true
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
        .statusBar(hidden: true)
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

    private func mangaChromeProgress(from presentation: MangaReaderPresentation) -> ReaderChromeProgress? {
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

        return ReaderChromeProgress(
            itemCount: itemCount,
            currentIndex: currentIndex,
            progressFraction: progressFraction,
            percentText: percentText,
            primaryText: L10n.string("manga.directory") + " · \(percentText)",
            secondaryText: L10n.string("manga.preview_page", currentIndex + 1, itemCount),
            ticks: [],
            scrubTargetIndexes: Array(0 ..< itemCount)
        )
    }
}

private struct MangaReaderFloatingControls: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let progress: ReaderChromeProgress?
    let onClose: () -> Void
    let onShowDirectory: () -> Void
    let onShowComments: () -> Void
    let onOpenOriginalPost: () -> Void
    let onJumpToLocalPage: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            ReaderGlassContainer(spacing: 10) {
                topControls
            }

            MangaReaderBottomControls(
                bottomInset: bottomInset,
                colorScheme: colorScheme,
                progress: progress,
                onShowDirectory: onShowDirectory,
                onShowComments: onShowComments,
                onJumpToLocalPage: onJumpToLocalPage
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            ReaderChromeCircleButton(
                systemName: "xmark",
                title: L10n.string("common.close"),
                tint: buttonTint,
                action: onClose
            )

            Spacer(minLength: 0)

            ReaderChromeCircleButton(
                systemName: "list.bullet",
                title: L10n.string("manga.directory"),
                tint: buttonTint,
                action: onShowDirectory
            )

            ReaderChromeCircleButton(
                systemName: "safari",
                title: L10n.string("common.original_post"),
                tint: buttonTint,
                action: onOpenOriginalPost
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(topInset + 8, 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var buttonTint: Color {
        readerChromeButtonTint(for: colorScheme)
    }
}

private struct MangaReaderBottomControls: View {
    let bottomInset: CGFloat
    let colorScheme: ColorScheme
    let progress: ReaderChromeProgress?
    let onShowDirectory: () -> Void
    let onShowComments: () -> Void
    let onJumpToLocalPage: (Int) -> Void

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        HStack(alignment: .bottom, spacing: layout.verticalScrubberSideSpacing) {
            Spacer(minLength: 0)
            VStack(spacing: layout.panelSpacing) {
                if let progress {
                    MangaReaderDirectoryProgressControl(
                        progress: progress,
                        onShowDirectory: onShowDirectory
                    )
                }

                MangaReaderStaticActionControls(
                    colorScheme: colorScheme,
                    commentsTitle: L10n.string("reader.comments"),
                    bookmarkTitle: "书签",
                    cacheTitle: L10n.string("reader.cache"),
                    onShowComments: onShowComments
                )
            }
            .frame(width: layout.maxChromeWidth)

            if let progress {
                MangaReaderVerticalProgressControl(
                    progress: progress,
                    onJumpToLocalPage: onJumpToLocalPage
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, max(bottomInset + 8, 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
    let onJumpToLocalPage: (Int) -> Void

    var body: some View {
        ReaderVerticalProgressCapsule(
            restingProgressFraction: progress.progressFraction,
            scrubContext: progress.scrubContext,
            ticks: progress.ticks,
            onBeginScrub: {},
            onCommit: onJumpToLocalPage,
            onEndScrub: {}
        )
        .frame(width: ReaderBottomChromeLayoutPresentation().verticalScrubberWidth, alignment: .trailing)
    }
}

private struct MangaReaderStaticActionControls: View {
    let colorScheme: ColorScheme
    let commentsTitle: String
    let bookmarkTitle: String
    let cacheTitle: String
    let onShowComments: () -> Void

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let buttonTint = readerChromeButtonTint(for: colorScheme)

        ReaderChromeCapsuleButton(
            title: commentsTitle,
            systemName: "text.bubble",
            action: onShowComments
        )

        HStack(spacing: layout.actionButtonSpacing) {
            ReaderChromeCircleButton(
                systemName: "bookmark",
                title: bookmarkTitle,
                tint: buttonTint,
                isEnabled: false,
                action: {}
            )
            ReaderChromeCircleButton(
                systemName: "square.and.arrow.down",
                title: cacheTitle,
                tint: buttonTint,
                isEnabled: false,
                action: {}
            )
        }
        .frame(height: layout.actionButtonRowHeight)
    }
}

private struct MangaReaderPresentationContent: View {
    let presentation: MangaReaderPresentation
    let imagePipeline: MangaImagePipeline?
    let onCurrentPageChange: (Int) -> Void

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
                    onCurrentPageChange: onCurrentPageChange
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

    var body: some View {
        if loaded.pages.isEmpty {
            MangaReaderEmptyContent()
        } else if let imagePipeline {
                MangaVerticalCollectionViewport(
                    pages: loaded.pages,
                    currentPageIndex: loaded.currentPageIndex,
                    viewportPlacement: loaded.viewportPlacement,
                    imagePipeline: imagePipeline,
                    onCurrentPageChange: onCurrentPageChange
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
