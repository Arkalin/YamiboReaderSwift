import Foundation

public enum YamiboThreadTaxonomy {
    public static let defaultNovelForumIDs: Set<String> = [
        "49",
        "55"
    ]

    public static let defaultMangaForumIDs: Set<String> = [
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
