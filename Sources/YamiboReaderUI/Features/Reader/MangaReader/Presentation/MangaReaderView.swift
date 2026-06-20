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
                    onClose: closeReader,
                    onShowDirectory: {
                        isDirectoryPresented = true
                    },
                    onOpenOriginalPost: openOriginalPost
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
}

private struct MangaReaderFloatingControls: View {
    let topInset: CGFloat
    let onClose: () -> Void
    let onShowDirectory: () -> Void
    let onOpenOriginalPost: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MangaReaderFloatingButton(
                systemName: "xmark",
                title: L10n.string("common.close"),
                action: onClose
            )

            Spacer(minLength: 0)

            MangaReaderFloatingButton(
                systemName: "list.bullet",
                title: L10n.string("manga.directory"),
                action: onShowDirectory
            )

            MangaReaderFloatingButton(
                systemName: "safari",
                title: L10n.string("common.original_post"),
                action: onOpenOriginalPost
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(topInset + 8, 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct MangaReaderFloatingButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.58), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
