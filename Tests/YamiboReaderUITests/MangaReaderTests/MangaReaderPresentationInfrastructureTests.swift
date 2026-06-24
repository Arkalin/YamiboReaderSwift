import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

#if os(iOS)
import UIKit
#endif

@Suite("MangaReaderTests: Presentation Infrastructure")
struct MangaReaderPresentationInfrastructureTests {
    #if os(iOS)
    @MainActor
    @Test func imagePipelineDeduplicatesConcurrentLoads() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [.success(Self.pngData)], delayNanoseconds: 50_000_000)
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        async let first = pipeline.image(for: page)
        async let second = pipeline.image(for: page)
        let images = try await [first, second]

        #expect(images.count == 2)
        #expect(images.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
        #expect(await loader.callCount == 1)
    }

    @MainActor
    @Test func imagePipelineCachesDecodedImages() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [.success(Self.pngData)])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        let first = try await pipeline.image(for: page)
        let second = try await pipeline.image(for: page)

        #expect(first === second)
        #expect(await loader.callCount == 1)
    }

    @MainActor
    @Test func imagePipelineDoesNotCacheInvalidImageData() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [
            .success(Data([0, 1, 2])),
            .success(Self.pngData)
        ])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        await #expect(throws: MangaImagePipelineError.invalidImageData) {
            _ = try await pipeline.image(for: page)
        }
        let image = try await pipeline.image(for: page)

        #expect(image.size.width > 0)
        #expect(await loader.callCount == 2)
    }

    @MainActor
    @Test func imagePipelineDoesNotCacheLoaderFailures() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [
            .failure(MangaPipelineTestError.loaderFailure),
            .success(Self.pngData)
        ])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        await #expect(throws: MangaPipelineTestError.loaderFailure) {
            _ = try await pipeline.image(for: page)
        }
        #expect(pipeline.cachedImage(for: page) == nil)
        let image = try await pipeline.image(for: page)

        #expect(image.size.width > 0)
        #expect(await loader.callCount == 2)
    }

    private static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
    #endif
}

#if os(iOS)
private enum MangaPipelineTestError: Error, Equatable {
    case loaderFailure
}

private actor RecordingMangaPipelineDataLoader: MangaImageDataLoading {
    private var outputs: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(outputs: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.outputs = outputs
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        callCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let output = outputs.isEmpty ? .success(Data()) : outputs.removeFirst()
        return try output.get()
    }
}

private func makePipelinePage() throws -> MangaReaderPageProjection {
    MangaReaderPageProjection(
        tid: "700",
        ownerPostID: "post-700",
        chapterTitle: "Chapter 700",
        imageURL: try #require(URL(string: "https://img.example.com/700-0.png")),
        refererURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=700")),
        globalIndex: 0,
        localIndex: 0,
        chapterPageCount: 1
    )
}
#endif
