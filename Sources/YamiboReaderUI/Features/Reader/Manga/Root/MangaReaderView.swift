import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let dependencies: MangaReaderDependencies
    private let appModel: YamiboAppModel
    @StateObject private var model: MangaReaderViewModel
    @State private var isDismissing = false
    @State private var isChromeVisible = true
    @State private var isDirectoryPresented = false
    @State private var isChapterCommentsPresented = false
    @State private var isSettingsPresented = false
    @State private var isCachePresented = false
    @State private var isLikesPresented = false
    @State private var likedItemForActionTarget: LikeItem?
    @State private var imageSavePresentation = MangaImageSavePresentationState()
    @State private var canRestoreMangaCover = false
    @State private var isSavingImage = false

    public init(context: MangaLaunchContext, dependencies: MangaReaderDependencies, appModel: YamiboAppModel) {
        self.context = context
        self.dependencies = dependencies
        self.appModel = appModel
        _model = StateObject(
            wrappedValue: MangaReaderViewModel(
                context: context,
                dependencies: dependencies,
                onReaderResumeRouteChange: { route in
                    appModel.updateReaderResumeRoute(route)
                }
            )
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)
            let usesTwoPageSpread = MangaPagedLayoutPolicy.usesTwoPageSpread(
                settings: model.presentation.settings,
                isPadDevice: UIDevice.current.userInterfaceIdiom == .pad,
                availableSize: proxy.size
            )

            MangaReaderPresentationContent(
                presentation: model.presentation,
                imageLoader: model.imageLoader,
                isChromeVisible: isChromeVisible,
                likedPageIDs: model.likedPageIDs,
                onRetryInitialLoad: {
                    Task { await model.retryInitialLoad() }
                },
                onCurrentPageChange: { globalIndex in
                    model.updateCurrentPage(globalIndex: globalIndex)
                },
                canBoundaryPageTurn: { delta, usesTwoPageSpread in
                    model.canJumpRelativePage(delta, usesTwoPageSpread: usesTwoPageSpread)
                },
                onBoundaryPageTurn: { delta, usesTwoPageSpread in
                    Task { await model.jumpRelativePage(delta, usesTwoPageSpread: usesTwoPageSpread) }
                },
                onPageLongPress: { page in
                    guard !isSavingImage else { return }
                    Task {
                        canRestoreMangaCover = await model.hasManualMangaCover()
                        likedItemForActionTarget = await model.isPageLiked(page)
                        imageSavePresentation.presentActions(for: page)
                    }
                },
                onTap: {
                    toggleChrome()
                }
            )
            .ignoresSafeArea()
            .overlay {
                ApplePencilPageTurnInteractionOverlay(
                    settings: model.applePencilPageTurnSettings,
                    canTurnPage: canReceiveApplePencilPageTurn
                ) { delta in
                    Task { await model.jumpRelativePage(delta, usesTwoPageSpread: usesTwoPageSpread) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .top) {
                MangaReaderChromeControls(
                    topInset: topInset,
                    bottomInset: bottomInset,
                    isVisible: isChromeVisible,
                    isPreview: context.isPreview,
                    imageLoader: model.imageLoader,
                    summary: mangaChromeSummary(
                        from: model.presentation,
                        usesTwoPageSpread: usesTwoPageSpread
                    ),
                    readingMode: model.presentation.settings.readingMode,
                    pageTurnDirection: model.presentation.settings.pageTurnDirection,
                    canNavigateBack: model.canNavigateBack,
                    canNavigateForward: model.canNavigateForward,
                    onNavigateBack: {
                        Task { await model.navigateBack() }
                    },
                    onNavigateForward: {
                        Task { await model.navigateForward() }
                    },
                    onClose: closeReader,
                    onShowDirectory: {
                        // Smart Comic Mode off (decision #2/#12): there is no
                        // `MangaDirectory` to show — `MangaReaderWorkflow`
                        // skipped resolution entirely and is holding a
                        // single-chapter pseudo-directory. The capsule itself
                        // keeps showing its own within-chapter page-progress
                        // text unaffected (that comes from `summary?.progress`
                        // independently of this closure); only the
                        // tap-to-open-directory-sheet interaction becomes a
                        // no-op.
                        guard model.context.isSmartModeEnabled else { return }
                        isDirectoryPresented = true
                    },
                    onShowComments: {
                        isChapterCommentsPresented = true
                    },
                    onShowSettings: {
                        isSettingsPresented = true
                    },
                    onShowCache: {
                        isCachePresented = true
                    },
                    onShowLikes: {
                        guard model.canShowLikes else { return }
                        isLikesPresented = true
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
            ReaderChapterCommentsSheet(
                target: model.currentChapterCommentTarget,
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                loadInitial: model.loadChapterComments(for:),
                refresh: model.refreshChapterComments(for:),
                loadNext: model.loadNextChapterCommentsPage,
                onOpenOriginalPost: openOriginalPostFromComments(_:)
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            MangaReaderSettingsSheet(model: model)
        }
        .sheet(isPresented: $isCachePresented) {
            if case let .loaded(loaded) = model.presentation.state {
                MangaReaderCacheSheet(
                    context: context,
                    panel: loaded.directoryPanel,
                    dependencies: dependencies
                )
            } else {
                MangaDirectoryUnavailableSheet()
            }
        }
        .sheet(isPresented: $isLikesPresented) {
            if let likeSheetContext = model.likeSheetContext {
                NavigationStack {
                    LikeWorkItemsView(
                        work: likeSheetContext.workKey,
                        workTitle: context.displayTitle,
                        like: likeSheetContext.like,
                        onOpenAnchor: { anchor in
                            isLikesPresented = false
                            Task {
                                await openLikedAnchor(anchor)
                            }
                        },
                        onDismiss: { isLikesPresented = false }
                    )
                }
            }
        }
        .confirmationDialog(
            L10n.string("image.actions.title"),
            isPresented: Binding(
                get: { imageSavePresentation.isActionDialogPresented },
                set: { imageSavePresentation.setActionDialogPresented($0) }
            ),
            titleVisibility: .visible
        ) {
            if let target = imageSavePresentation.actionTarget {
                Button(L10n.string("image.save_to_photos")) {
                    Task {
                        await saveImage(target.page)
                    }
                }
                .disabled(isSavingImage)

                if model.canSetMangaCover {
                    Button(L10n.string("cover.set_as_cover")) {
                        Task {
                            await setMangaCover(target.page)
                        }
                    }
                    if canRestoreMangaCover {
                        Button(L10n.string("cover.restore_auto_cover")) {
                            Task {
                                await restoreMangaCover()
                            }
                        }
                    }
                }

                if let likedItem = likedItemForActionTarget {
                    Button(L10n.string("likes.remove_like"), role: .destructive) {
                        Task {
                            await unlikePage(likedItem)
                        }
                    }
                } else {
                    Button(L10n.string("likes.add_to_likes")) {
                        Task {
                            await likePage(target.page)
                        }
                    }
                }
            }

            Button(L10n.string("common.cancel"), role: .cancel) {
                imageSavePresentation.clearActionTarget()
                likedItemForActionTarget = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback = imageSavePresentation.feedback {
                MangaImageSaveFeedbackToast(feedback: feedback)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: imageSavePresentation.feedback?.id)
        .task(id: imageSavePresentation.feedback?.id) {
            guard let feedback = imageSavePresentation.feedback else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                imageSavePresentation.clearFeedback(id: feedback.id)
            }
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

    private var canReceiveApplePencilPageTurn: Bool {
        guard case let .loaded(loaded) = model.presentation.state else { return false }
        return UIDevice.current.userInterfaceIdiom == .pad &&
            model.presentation.settings.readingMode == .paged &&
            !loaded.pages.isEmpty &&
            !isDirectoryPresented &&
            !isChapterCommentsPresented &&
            !isSettingsPresented &&
            !isCachePresented &&
            !isDismissing &&
            !isChromeVisible
    }

    private func closeReader() {
        guard !isDismissing else { return }
        isDismissing = true
        Task {
            await model.saveProgress()
            appModel.dismissMangaReader()
        }
    }

    private func openOriginalPost() {
        guard !isDismissing else { return }
        isDismissing = true
        Task {
            let latestContext = await model.saveProgress()
            appModel.dismissMangaReader(
                openThreadInForum: YamiboRoute.threadByID(
                    tid: context.originalThreadID,
                    page: 1,
                    authorID: nil,
                    reverse: false
                ).url,
                suspendedMangaContext: latestContext
            )
        }
    }

    private func openOriginalPostFromComments(_ url: URL) {
        guard !isDismissing else { return }
        isDismissing = true
        appModel.dismissMangaReader(openThreadInForum: url)
    }

    @MainActor
    private func saveImage(_ page: MangaReaderPageProjection) async {
        guard !isSavingImage else { return }
        imageSavePresentation.clearActionTarget()

        isSavingImage = true
        defer {
            isSavingImage = false
        }

        do {
            let data = try await YamiboImagePipeline.shared.data(for: model.imageSource(for: page))
            let photoSaver = MangaImagePhotoSaver()
            try await photoSaver.saveImageData(data)
            imageSavePresentation.finishSave(with: .success)
        } catch MangaImagePhotoSaveError.authorizationDenied {
            YamiboLog.reader.warning("Manga page image save denied: Photos authorization was not granted")
            imageSavePresentation.finishSave(with: .failure(message: L10n.string("image.save_photo_permission_denied")))
        } catch {
            YamiboLog.reader.error("Failed to save manga page image: \(error.localizedDescription)")
            imageSavePresentation.finishSave(with: .failure(message: L10n.string("image.save_failed")))
        }
    }

    @MainActor
    private func setMangaCover(_ page: MangaReaderPageProjection) async {
        imageSavePresentation.clearActionTarget()
        let succeeded = await model.setMangaCover(page: page)
        imageSavePresentation.finishSave(with: succeeded
            ? .custom(
                title: L10n.string("cover.action_success_title"),
                message: L10n.string("cover.set_success_message")
            )
            : .failure(message: L10n.string("image.action_failed")))
    }

    @MainActor
    private func restoreMangaCover() async {
        imageSavePresentation.clearActionTarget()
        let succeeded = await model.restoreAutomaticMangaCover()
        imageSavePresentation.finishSave(with: succeeded
            ? .custom(
                title: L10n.string("cover.action_success_title"),
                message: L10n.string("cover.restore_success_message")
            )
            : .failure(message: L10n.string("image.action_failed")))
    }

    @MainActor
    private func likePage(_ page: MangaReaderPageProjection) async {
        imageSavePresentation.clearActionTarget()
        likedItemForActionTarget = nil
        guard let outcome = await model.likePage(page) else {
            imageSavePresentation.finishSave(with: .failure(message: L10n.string("image.action_failed")))
            return
        }
        switch outcome {
        case .added, .merged, .alreadyLiked:
            imageSavePresentation.finishSave(with: .custom(
                title: L10n.string("likes.already_liked"),
                message: ""
            ))
        }
    }

    @MainActor
    private func unlikePage(_ item: LikeItem) async {
        imageSavePresentation.clearActionTarget()
        likedItemForActionTarget = nil
        let succeeded = await model.unlikePage(item)
        imageSavePresentation.finishSave(with: succeeded
            ? .custom(title: L10n.string("likes.remove_like"), message: "")
            : .failure(message: L10n.string("image.action_failed")))
    }

    private func openLikedAnchor(_ anchor: LikeAnchorPayload) async {
        guard case let .mangaImage(mangaAnchor) = anchor else { return }
        if await model.jumpToLikedMangaPage(tid: mangaAnchor.chapterTID, localIndex: mangaAnchor.pageLocalIndex) {
            return
        }
        appModel.presentMangaReader(
            MangaLaunchContext(
                originalThreadID: context.originalThreadID,
                chapterTID: mangaAnchor.chapterTID,
                displayTitle: context.displayTitle,
                source: .like,
                initialPage: mangaAnchor.pageLocalIndex,
                directoryName: context.directoryName,
                offlineCacheFavoriteID: context.offlineCacheFavoriteID,
                isSmartModeEnabled: context.isSmartModeEnabled
            )
        )
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private func mangaChromeSummary(
        from presentation: MangaReaderPresentation,
        usesTwoPageSpread: Bool
    ) -> MangaReaderChromeSummary? {
        guard case let .loaded(loaded) = presentation.state,
              !loaded.pages.isEmpty else {
            return nil
        }

        let pages = loaded.pages
        let currentPage = loaded.currentPage
            ?? loaded.currentPageIndex.flatMap { pages.indices.contains($0) ? pages[$0] : nil }
            ?? pages[0]
        let currentPageIndex = loaded.currentPageIndex ?? pages.firstIndex(of: currentPage)
        let itemCount = max(currentPage.chapterPageCount, 1)
        let maxIndex = max(itemCount - 1, 1)
        let currentIndex = min(max(currentPage.localIndex, 0), itemCount - 1)
        let progressFraction = itemCount > 1 ? Double(currentIndex) / Double(maxIndex) : 0
        let percentText = "\(Int((progressFraction * 100).rounded()))%"
        let pageLabel = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: currentPageIndex,
            pageTurnDirection: presentation.settings.pageTurnDirection,
            usesTwoPageSpread: usesTwoPageSpread
        ).currentChapterPageLabel
        let pageSummary = L10n.string("manga.preview_page_label", pageLabel, itemCount)
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
        let capsuleTitleKey = context.isSmartModeEnabled ? "manga.directory" : "manga.progress"
        let capsuleIconSystemName = context.isSmartModeEnabled ? "list.bullet" : "chart.bar.fill"

        return MangaReaderChromeSummary(
            headerTitle: headerTitle,
            pageSummary: pageSummary,
            pagePreviewTargets: pagePreviewTargets,
            progress: ReaderChromeProgress(
                itemCount: itemCount,
                currentIndex: currentIndex,
                progressFraction: progressFraction,
                percentText: percentText,
                primaryText: L10n.string(capsuleTitleKey) + " · \(percentText)",
                secondaryText: pageSummary,
                ticks: [],
                iconSystemName: capsuleIconSystemName,
                scrubTargetIndexes: Array(0 ..< itemCount)
            )
        )
    }
}

#endif
