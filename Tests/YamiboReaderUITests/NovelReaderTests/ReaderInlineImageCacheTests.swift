#if os(iOS)
import UIKit
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderInlineImageCacheTests: XCTestCase {
    func testMemoryCacheScopesDecodedImagesByNamespace() {
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        let refererURL = URL(string: "https://bbs.yamibo.com/forum.php?tid=42")!
        let firstIdentity = ReaderInlineImageRequestIdentity(
            url: imageURL,
            refererURL: refererURL,
            cacheNamespace: NovelInlineImageCacheNamespace(value: "first-\(UUID().uuidString)")
        )
        let secondIdentity = ReaderInlineImageRequestIdentity(
            url: imageURL,
            refererURL: refererURL,
            cacheNamespace: NovelInlineImageCacheNamespace(value: "second-\(UUID().uuidString)")
        )
        let firstImage = testImage(color: .red)
        let secondImage = testImage(color: .blue)

        ReaderInlineImageMemoryCache.store(firstImage, for: firstIdentity)
        ReaderInlineImageMemoryCache.store(secondImage, for: secondIdentity)

        XCTAssertTrue(ReaderInlineImageMemoryCache.image(for: firstIdentity) === firstImage)
        XCTAssertTrue(ReaderInlineImageMemoryCache.image(for: secondIdentity) === secondImage)
    }
}

private func testImage(color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
        color.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
    }
}
#endif
