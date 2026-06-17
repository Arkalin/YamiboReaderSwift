import SwiftUI
import YamiboReaderCore

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        NavigationStack {
            MangaReaderSkeletonContent(
                title: context.displayTitle,
                chapterURL: context.chapterURL,
                originalThreadURL: context.originalThreadURL
            )
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

private struct MangaReaderSkeletonContent: View {
    let title: String
    let chapterURL: URL
    let originalThreadURL: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MangaReaderSkeletonHeader(title: title)
                MangaReaderSkeletonStatus()
                MangaReaderSkeletonRouteDetails(
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

private struct MangaReaderSkeletonHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("manga.reader.title"), systemImage: "book.pages")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(title.isEmpty ? L10n.string("manga.reader.title") : title)
                .font(.title2)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MangaReaderSkeletonStatus: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("manga.skeleton.empty_title"), systemImage: "hammer")
                .font(.headline)

            Text(L10n.string("manga.skeleton.empty_message"))
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

private struct MangaReaderSkeletonRouteDetails: View {
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
