import Foundation

enum FavoriteLibraryURLIdentity {
    static func canonicalThreadURL(from url: URL) -> URL {
        YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url)
    }

    static func canonicalThreadURLKey(for url: URL) -> String {
        YamiboThreadURLCanonicalizer.canonicalThreadURLKey(for: url)
    }

    static func favorite(_ favorite: Favorite, matches url: URL) -> Bool {
        YamiboThreadURLCanonicalizer.threadID(from: url) == favorite.threadID
    }

}
