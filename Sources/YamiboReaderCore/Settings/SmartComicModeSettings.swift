import Foundation

/// Per-board opt-in for Smart Comic Mode (智能漫画模式).
///
/// Scope is fixed to the three existing hardcoded manga forum IDs already
/// classified by `YamiboThreadTaxonomy.defaultMangaForumIDs` — this settings
/// type is only the on/off toggle for those boards, not a place to add new
/// manga boards (smart-comic-mode design decision #1). Which boards *are*
/// manga boards (thread-kind classification, used for favorite target kind
/// and reading-progress bookkeeping) stays governed entirely by
/// `YamiboThreadTaxonomy` and is deliberately independent of this toggle
/// (decision #4): flipping a board's switch never reclassifies its threads.
public struct SmartComicModeSettings: Codable, Hashable, Sendable {
    /// The only forum IDs this toggle applies to.
    public static let manageableForumIDs: Set<String> = ["30", "46", "37"]

    /// Default per decision #1: fid 30 (中文百合漫画区) on, 46/37 off.
    public static let defaultEnabledForumIDs: Set<String> = ["30"]

    public var enabledForumIDs: Set<String>

    public init(enabledForumIDs: Set<String> = Self.defaultEnabledForumIDs) {
        self.enabledForumIDs = enabledForumIDs
    }

    /// Whether Smart Comic Mode is on for `forumID`.
    ///
    /// Boards outside `manageableForumIDs` — including a missing/blank fid —
    /// always report enabled: they have no toggle, so callers should treat
    /// them exactly like the pre-Phase-B unconditional manga routing/reader
    /// behavior. Only the three manageable boards can ever report `false`.
    public func isEnabled(forumID: String?) -> Bool {
        guard let normalized = forumID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return true
        }
        guard Self.manageableForumIDs.contains(normalized) else {
            return true
        }
        return enabledForumIDs.contains(normalized)
    }
}
