import Foundation

public enum ReaderModeDetector {
    private static let textSections = ["文學區", "文学区", "轻小说/译文区", "TXT小说区"]

    public static func canOpenReader(url: URL?, title: String?) -> Bool {
        guard let url else { return false }
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let absolute = url.absoluteString
        guard absolute.contains("mod=viewthread"), absolute.contains("tid=") else { return false }
        return textSections.contains { title.contains($0) }
    }

    public static func canonicalThreadURL(from fullURL: URL?) -> URL? {
        guard let fullURL else { return nil }
        if fullURL.host == nil {
            return URL(string: fullURL.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL
        }
        if fullURL.host?.contains("yamibo.com") == true {
            return fullURL.absoluteURL
        }
        return nil
    }
}
