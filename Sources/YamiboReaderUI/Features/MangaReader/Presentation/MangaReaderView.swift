import SwiftUI
import YamiboReaderCore

#if os(iOS)
public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel
    @StateObject private var model: MangaReaderModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
        _model = StateObject(
            wrappedValue: MangaReaderModel(context: context, appContext: appModel.appContext)
        )
    }

    public var body: some View {
        NavigationStack {
            MangaReaderPresentationContent(
                presentation: model.presentation,
                imagePipeline: model.imagePipeline,
                onCurrentPageChange: { globalIndex in
                    model.updateCurrentPage(globalIndex: globalIndex)
                }
            )
            .task {
                await model.prepare()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        appModel.dismissManga()
                    } label: {
                        Label(L10n.string("common.close"), systemImage: "xmark")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appModel.dismissManga(openThreadInForum: context.originalThreadURL)
                    } label: {
                        Label(L10n.string("common.original_post"), systemImage: "safari")
                    }
                }
            }
            .navigationTitle(L10n.string("manga.reader.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
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
