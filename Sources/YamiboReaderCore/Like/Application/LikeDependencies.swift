import Foundation

/// Dependency package the My Likes feature and both readers share to build
/// their capture services and list views from the same infrastructure.
public struct LikeDependencies: Sendable {
    public let likeStore: LikeStore
    public let likeImageStore: LikeImageStore
    /// Resolves manga chapter order for the second-level Like list; manga
    /// Like Items don't store a chapter ordinal (see implementation-design §11).
    public let mangaDirectoryStore: MangaDirectoryStore

    public init(
        likeStore: LikeStore,
        likeImageStore: LikeImageStore,
        mangaDirectoryStore: MangaDirectoryStore
    ) {
        self.likeStore = likeStore
        self.likeImageStore = likeImageStore
        self.mangaDirectoryStore = mangaDirectoryStore
    }
}
