import SwiftUI
import YamiboReaderCore
import UIKit

/// Second-level Like list for one work: Mine push destination and both
/// readers' `.sheet` share this exact type (see implementation-design.md §9).
struct LikeWorkItemsView: View {
    let work: LikeWorkKey
    let workTitle: String
    let like: LikeDependencies
    let onOpenAnchor: (LikeAnchorPayload) -> Void
    let onDismiss: (() -> Void)?

    @State private var items: [LikeItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(L10n.string("likes.empty_state"), systemImage: "heart")
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            onOpenAnchor(item.anchor)
                        } label: {
                            LikeItemRowContent(item: item, likeImageStore: like.likeImageStore)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label(L10n.string("common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(workTitle)
        .toolbar {
            if let onDismiss {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close"), action: onDismiss)
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: LikeStore.didChangeNotification)) { notification in
            guard let changeID = notification.userInfo?[LikeStore.changeIDUserInfoKey] as? String,
                  changeID == like.likeStore.changeID else {
                return
            }
            Task { await load() }
        }
    }

    private func load() async {
        let fetched = await like.likeStore.likes(for: work)
        switch work.kind {
        case .novel:
            items = Self.sortedNovelItems(fetched)
        case .manga:
            // Manga Like Items never store a chapter ordinal (see
            // implementation-design.md §11): chapter order is always resolved
            // live against the directory's current chapter array.
            let directory = try? await like.mangaDirectoryStore.directory(named: work.id)
            items = Self.sortedMangaItems(fetched, chapterOrder: Self.chapterOrder(for: directory))
        }
    }

    private func delete(_ item: LikeItem) {
        Task {
            try? await like.likeStore.delete(id: item.id)
            if item.kind == .image {
                try? await like.likeImageStore.delete(id: item.id)
            }
            await load()
        }
    }

    private struct NovelLikeSortKey {
        var chapterIdentity: String
        var occurrence: Int
        var offset: Int
    }

    private static func sortedNovelItems(_ items: [LikeItem]) -> [LikeItem] {
        items.sorted { lhs, rhs in
            let lhsKey = novelSortKey(for: lhs)
            let rhsKey = novelSortKey(for: rhs)
            if lhsKey.chapterIdentity != rhsKey.chapterIdentity {
                return lhsKey.chapterIdentity < rhsKey.chapterIdentity
            }
            if lhsKey.occurrence != rhsKey.occurrence {
                return lhsKey.occurrence < rhsKey.occurrence
            }
            return lhsKey.offset < rhsKey.offset
        }
    }

    private static func novelSortKey(for item: LikeItem) -> NovelLikeSortKey {
        switch item.anchor {
        case let .novelText(anchor):
            return NovelLikeSortKey(
                chapterIdentity: anchor.chapterIdentity.rawValue,
                occurrence: LikeTextSegmentOccurrence.occurrence(of: anchor.textSegmentIdentity.rawValue) ?? 0,
                offset: anchor.range.location
            )
        case let .novelImage(anchor):
            return NovelLikeSortKey(
                chapterIdentity: anchor.chapterIdentity.rawValue,
                occurrence: LikeTextSegmentOccurrence.occurrence(of: anchor.imageSegmentIdentity) ?? 0,
                offset: 0
            )
        case .mangaImage:
            return NovelLikeSortKey(chapterIdentity: "", occurrence: 0, offset: 0)
        }
    }

    // Mirrors `MangaChapterWindow.chapterOrder()`: first occurrence wins so a
    // directory with a duplicate tid doesn't crash on dictionary insertion.
    private static func chapterOrder(for directory: MangaDirectory?) -> [String: Int] {
        var order: [String: Int] = [:]
        for (index, chapter) in (directory?.chapters ?? []).enumerated() where order[chapter.tid] == nil {
            order[chapter.tid] = index
        }
        return order
    }

    private static func sortedMangaItems(_ items: [LikeItem], chapterOrder: [String: Int]) -> [LikeItem] {
        items.sorted { lhs, rhs in
            guard case let .mangaImage(lhsAnchor) = lhs.anchor,
                  case let .mangaImage(rhsAnchor) = rhs.anchor else {
                return false
            }
            let lhsOrder = chapterOrder[lhsAnchor.chapterTID] ?? Int.max
            let rhsOrder = chapterOrder[rhsAnchor.chapterTID] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhsAnchor.pageLocalIndex < rhsAnchor.pageLocalIndex
        }
    }
}

/// `NovelLikeTextEndpointOrdering.occurrence(of:)` (Core) is internal and
/// invisible across the Core/UI module boundary, so this reimplements the
/// same "#text:N" / "#image:N" suffix parse for sorting purposes only.
private enum LikeTextSegmentOccurrence {
    private static let occurrenceSuffixRegex = try! NSRegularExpression(pattern: #"#(?:text|image):(\d+)$"#)

    static func occurrence(of segmentIdentity: String) -> Int? {
        let range = NSRange(segmentIdentity.startIndex..<segmentIdentity.endIndex, in: segmentIdentity)
        guard let match = occurrenceSuffixRegex.firstMatch(in: segmentIdentity, range: range),
              let numberRange = Range(match.range(at: 1), in: segmentIdentity) else {
            return nil
        }
        return Int(segmentIdentity[numberRange])
    }
}

private struct LikeItemRowContent: View {
    let item: LikeItem
    let likeImageStore: LikeImageStore

    var body: some View {
        switch item.kind {
        case .text:
            Text(item.excerptText ?? "")
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        case .image:
            HStack {
                LikeImageThumbnail(item: item, likeImageStore: likeImageStore)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LikeImageThumbnail: View {
    let item: LikeItem
    let likeImageStore: LikeImageStore

    @State private var localData: Data?
    @State private var didFinishLocalLookup = false

    var body: some View {
        Group {
            if let localData, let uiImage = UIImage(data: localData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if didFinishLocalLookup {
                YamiboRemoteImage(source: item.sourceImageURL.map { YamiboImageSource(url: $0) }) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.12)
                } failure: {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            localData = await likeImageStore.loadData(id: item.id)
            didFinishLocalLookup = true
        }
    }
}
