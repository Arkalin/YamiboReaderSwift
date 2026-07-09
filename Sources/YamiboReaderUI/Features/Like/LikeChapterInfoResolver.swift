import Foundation
import YamiboReaderCore

/// Best-effort chapter-title lookup for Like item cards. Like anchors never
/// persist a chapter title (see implementation-design.md §11's "resolve
/// live, don't persist a value that can drift" philosophy, already applied
/// to manga chapter order) — novel titles are read back from the disk-cached
/// `NovelReaderProjection` instead. A cache miss (page never opened as a
/// reader view, or since evicted) simply yields no chapter info; the card
/// falls back to showing just the excerpt/image with no chapter caption.
enum LikeChapterInfoResolver {
    /// The forum page (`NovelPageRequest.view`) an anchor's segment lives on,
    /// used to fetch the right cached projection.
    static func documentView(for anchor: LikeAnchorPayload) -> Int {
        switch anchor {
        case let .novelText(textAnchor):
            return textAnchor.chapterIdentity.embeddedDocumentView ?? 1
        case let .novelImage(imageAnchor):
            return imageAnchor.chapterIdentity.embeddedDocumentView ?? 1
        case .mangaImage:
            return 1
        }
    }

    /// Matches the anchor's segment identity against `projection.segmentSemantics`
    /// and reads the corresponding `NovelReaderSegment.chapterTitle`.
    static func novelChapterTitle(
        for anchor: LikeAnchorPayload,
        in projection: NovelReaderProjection?
    ) -> String? {
        guard let projection else { return nil }
        let segmentIdentity: String
        switch anchor {
        case let .novelText(textAnchor):
            segmentIdentity = textAnchor.textSegmentIdentity.rawValue
        case let .novelImage(imageAnchor):
            segmentIdentity = imageAnchor.imageSegmentIdentity
        case .mangaImage:
            return nil
        }
        guard let index = projection.segmentSemantics.firstIndex(where: {
            $0?.textSegmentIdentity?.rawValue == segmentIdentity
        }) else {
            return nil
        }
        return trimmedOrNil(projection.segments[index].chapterTitle)
    }

    /// Resolves chapter titles for a batch of novel Like items, caching one
    /// projection load per distinct `view` so a list of many items on the
    /// same forum page doesn't re-read the disk cache per item.
    static func novelChapterInfo(
        for items: [LikeItem],
        threadID: String,
        cacheStore: NovelReaderProjectionStore
    ) async -> [String: String] {
        var projectionsByView: [Int: NovelReaderProjection] = [:]
        var attemptedViews: Set<Int> = []
        var result: [String: String] = [:]

        for item in items {
            let view = documentView(for: item.anchor)
            if !attemptedViews.contains(view) {
                attemptedViews.insert(view)
                if let projection = await cacheStore.loadProjection(for: NovelPageRequest(threadID: threadID, view: view)) {
                    projectionsByView[view] = projection
                }
            }
            if let title = novelChapterTitle(for: item.anchor, in: projectionsByView[view]) {
                result[item.id] = title
            }
        }
        return result
    }

    /// Resolves chapter titles for a batch of manga Like items from the
    /// (already-loaded) manga directory's chapter list, matched by `tid`.
    static func mangaChapterInfo(for items: [LikeItem], directory: MangaDirectory?) -> [String: String] {
        guard let directory else { return [:] }
        var titleByTID: [String: String] = [:]
        for chapter in directory.chapters where titleByTID[chapter.tid] == nil {
            if let title = trimmedOrNil(chapter.rawTitle) {
                titleByTID[chapter.tid] = title
            }
        }
        var result: [String: String] = [:]
        for item in items {
            guard case let .mangaImage(anchor) = item.anchor, let title = titleByTID[anchor.chapterTID] else { continue }
            result[item.id] = title
        }
        return result
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
