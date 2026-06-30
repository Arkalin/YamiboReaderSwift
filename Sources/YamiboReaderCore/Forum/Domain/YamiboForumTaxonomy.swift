import Foundation

public enum YamiboForumTaxonomy {
    public static let defaultNovelForumIDs: Set<String> = [
        "75"
    ]

    public static let defaultMangaForumIDs: Set<String> = [
        "30"
    ]

    public static func threadKind(for fid: String) -> YamiboForumThreadKind {
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
