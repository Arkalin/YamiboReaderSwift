import Foundation

public enum ReaderDebugLog {
    public static func log(_ message: String) {
#if DEBUG
        NSLog("[YamiboReaderDebug] \(message)")
#endif
    }
}

public extension String {
    var readerDebugSnippet: String {
        let normalized = replacingOccurrences(of: "\n", with: "\\n")
        return String(normalized.prefix(40))
    }
}
