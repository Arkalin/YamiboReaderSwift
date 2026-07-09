import Foundation

/// Public (smart-comic-mode Phase F): `FavoriteQuickActions` classifies a
/// star-button favorite's target kind by board fid, and it lives in the
/// separate `YamiboReaderUI` module — `threadKind(for:)` (and the enclosing
/// namespace) must cross the module boundary. The two hardcoded ID sets stay
/// internal; nothing outside this module needs them directly, only the
/// classification result.
public enum YamiboThreadTaxonomy {
    static let defaultNovelForumIDs: Set<String> = [
        "49",
        "55"
    ]

    static let defaultMangaForumIDs: Set<String> = [
        "46",
        "30",
        "37"
    ]

    public static func threadKind(for fid: String) -> YamiboThreadKind {
        let normalized = fid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .unknown }
        if defaultNovelForumIDs.contains(normalized) {
            return .novel
        }
        if defaultMangaForumIDs.contains(normalized) {
            return .manga
        }
        return .unknown
    }
}
