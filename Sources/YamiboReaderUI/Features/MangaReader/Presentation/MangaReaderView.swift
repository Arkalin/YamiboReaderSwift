import SwiftUI
import YamiboReaderCore

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
                chapterURL: context.chapterURL,
                originalThreadURL: context.originalThreadURL
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

private struct MangaReaderPresentationContent: View {
    let presentation: MangaReaderPresentation
    let chapterURL: URL
    let originalThreadURL: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch presentation.state {
                case let .loading(loading):
                    MangaReaderLoadingContent(title: loading.title)
                case let .loaded(loaded):
                    MangaReaderLoadedContent(loaded: loaded)
                case let .failed(error):
                    MangaReaderFailedContent(error: error)
                }
                MangaReaderRouteDetails(
                    chapterURL: chapterURL,
                    originalThreadURL: originalThreadURL
                )
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
    }
}

private struct MangaReaderLoadingContent: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MangaReaderTitleHeader(title: title)
            ProgressView(L10n.string("manga.loading"))
                .tint(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MangaReaderLoadedContent: View {
    let loaded: MangaReaderLoadedPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MangaReaderLoadedHeader(
                title: loaded.title,
                directoryTitle: loaded.directoryTitle,
                currentPage: loaded.currentPage,
                currentPageIndex: loaded.currentPageIndex,
                pageCount: loaded.pages.count
            )
            MangaReaderPageProjectionList(pages: loaded.pages, currentPageID: loaded.currentPage?.id)
        }
    }
}

private struct MangaReaderFailedContent: View {
    let error: MangaReaderErrorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(error.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MangaReaderTitleHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

private struct MangaReaderLoadedHeader: View {
    let title: String
    let directoryTitle: String
    let currentPage: MangaReaderPageProjection?
    let currentPageIndex: Int?
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaReaderTitleHeader(title: title)

            VStack(alignment: .leading, spacing: 8) {
                Label(directoryTitle, systemImage: "list.bullet.rectangle")
                    .font(.headline)

                if let currentPage {
                    Text(L10n.string("manga.preview_page", currentPage.localIndex + 1, currentPage.chapterPageCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(currentPage.chapterTitle)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.string("manga.no_chapters"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let currentPageIndex {
                    Text(L10n.string("manga.reader.current_index", currentPageIndex + 1, max(pageCount, 1)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MangaReaderPageProjectionList: View {
    let pages: [MangaReaderPageProjection]
    let currentPageID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.string("manga.reader.loaded_pages_count", pages.count), systemImage: "photo.on.rectangle")
                .font(.headline)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(pages) { page in
                    MangaReaderPageProjectionRow(
                        page: page,
                        isCurrent: page.id == currentPageID
                    )
                }
            }
        }
    }
}

private struct MangaReaderPageProjectionRow: View {
    let page: MangaReaderPageProjection
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    L10n.string("manga.preview_page", page.localIndex + 1, page.chapterPageCount),
                    systemImage: isCurrent ? "location.fill" : "photo"
                )
                .font(.subheadline)
                .fontWeight(isCurrent ? .semibold : .regular)

                Spacer(minLength: 8)

                Text(verbatim: "tid \(page.tid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(page.chapterTitle)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.imageURL.absoluteString)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.accentColor.opacity(0.24) : .white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MangaReaderRouteDetails: View {
    let chapterURL: URL
    let originalThreadURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaReaderRouteRow(
                title: L10n.string("manga.skeleton.current_url"),
                url: chapterURL
            )
            MangaReaderRouteRow(
                title: L10n.string("manga.skeleton.original_thread"),
                url: originalThreadURL
            )
        }
    }
}

struct MangaReaderRouteRow: View {
    let title: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
