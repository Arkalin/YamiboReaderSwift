import CryptoKit
import Foundation

public enum ReaderDocumentFingerprint {
    public static func fingerprint(for document: ReaderPageDocument) -> String {
        var payload = "yamibo-reader-document-v1\n"
        for segment in document.segments {
            switch segment {
            case let .text(text, chapterTitle):
                payload += "text\n"
                payload += normalized(chapterTitle)
                payload += "\n"
                payload += normalized(text)
                payload += "\n"
            case let .image(url, chapterTitle):
                payload += "image\n"
                payload += normalized(chapterTitle)
                payload += "\n"
                payload += url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
                payload += "\n"
            }
        }

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
