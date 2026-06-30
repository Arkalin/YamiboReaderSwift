#if os(iOS)
import UIKit
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderInlineImageCacheTests: XCTestCase {
    @MainActor
    func testMemoryCacheScopesDecodedImagesByNamespace() async throws {
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        let refererURL = URL(string: "https://bbs.yamibo.com/forum.php?tid=42")!
        let firstRequest = YamiboImageRequest(
            url: imageURL,
            refererURL: refererURL,
            cacheNamespace: YamiboImageCacheNamespace(value: "first-\(UUID().uuidString)")
        )
        let secondRequest = YamiboImageRequest(
            url: imageURL,
            refererURL: refererURL,
            cacheNamespace: YamiboImageCacheNamespace(value: "second-\(UUID().uuidString)")
        )
        let pipeline = YamiboImagePipeline()
        let loader = NamespaceImageDataLoader(outputs: [
            firstRequest.cacheNamespace.value: testImageData(color: .red),
            secondRequest.cacheNamespace.value: testImageData(color: .blue)
        ])

        let firstImage = try await pipeline.image(for: firstRequest, dataLoader: loader)
        let secondImage = try await pipeline.image(for: secondRequest, dataLoader: loader)

        XCTAssertTrue(pipeline.cachedImage(for: firstRequest) === firstImage)
        XCTAssertTrue(pipeline.cachedImage(for: secondRequest) === secondImage)
        XCTAssertFalse(firstImage === secondImage)
    }

    @MainActor
    func testImagePipelineDeduplicatesConcurrentLoads() async throws {
        let request = YamiboImageRequest(
            url: URL(string: "https://img.example.com/dedupe.jpg")!,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=42")!,
            cacheNamespace: YamiboImageCacheNamespace(value: "dedupe-\(UUID().uuidString)")
        )
        let pipeline = YamiboImagePipeline()
        let loader = SequencedImageDataLoader(outputs: [.success(testImageData(color: .red))], delayNanoseconds: 50_000_000)

        async let first = pipeline.image(for: request, dataLoader: loader)
        async let second = pipeline.image(for: request, dataLoader: loader)
        _ = try await [first, second]

        let callCount = await loader.loadCallCount()
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testImagePipelineDoesNotCacheDecodeFailures() async throws {
        let request = YamiboImageRequest(
            url: URL(string: "https://img.example.com/retry.jpg")!,
            refererURL: nil,
            cacheNamespace: YamiboImageCacheNamespace(value: "retry-\(UUID().uuidString)")
        )
        let pipeline = YamiboImagePipeline()
        let loader = SequencedImageDataLoader(outputs: [
            .success(Data([0, 1, 2])),
            .success(testImageData(color: .blue))
        ])

        do {
            _ = try await pipeline.image(for: request, dataLoader: loader)
            XCTFail("Expected invalid image data")
        } catch YamiboImagePipelineError.invalidImageData {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.image(for: request, dataLoader: loader)

        XCTAssertNotNil(pipeline.cachedImage(for: request))
        let callCount = await loader.loadCallCount()
        XCTAssertEqual(callCount, 2)
    }
}

private actor NamespaceImageDataLoader: YamiboImageDataLoading {
    private let outputs: [String: Data]

    init(outputs: [String: Data]) {
        self.outputs = outputs
    }

    func imageData(for request: YamiboImageRequest) async throws -> Data {
        try XCTUnwrap(outputs[request.cacheNamespace.value])
    }
}

private actor SequencedImageDataLoader: YamiboImageDataLoading {
    private var outputs: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(outputs: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.outputs = outputs
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for _: YamiboImageRequest) async throws -> Data {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let output = outputs.isEmpty ? .failure(TestImageDataLoaderError.exhausted) : outputs.removeFirst()
        return try output.get()
    }

    func loadCallCount() -> Int {
        callCount
    }
}

private enum TestImageDataLoaderError: Error {
    case exhausted
}

private func testImageData(color: UIColor) -> Data {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
        color.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
    }
    return image.pngData()!
}
#endif
