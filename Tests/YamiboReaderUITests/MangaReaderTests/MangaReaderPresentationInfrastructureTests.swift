import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

#if os(iOS)
import UIKit
#endif

@Suite("MangaReaderTests: Presentation Infrastructure")
struct MangaReaderPresentationInfrastructureTests {
    @Test func verticalViewportUsesUIKitCompositionalLayout() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")

        #expect(source.contains("struct MangaVerticalCollectionViewport: UIViewRepresentable"))
        #expect(source.contains("UICollectionView"))
        #expect(source.contains("UICollectionViewCompositionalLayout"))
        #expect(!source.contains("LazyVStack"))
    }

    @Test func readerLoadedStateDoesNotUseDiagnosticScrollList() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        #expect(source.contains("MangaVerticalCollectionViewport("))
        #expect(source.contains("MangaPagedReaderViewport("))
        #expect(source.contains("switch settings.readingMode"))
        #expect(source.contains("case .vertical:"))
        #expect(source.contains("case .paged:"))
        #expect(!source.contains("ScrollView"))
        #expect(!source.contains("LazyVStack"))
        #expect(!source.contains("MangaReaderRouteDetails"))
        #expect(!source.contains("chapterURL:"))
        #expect(!source.contains("originalThreadURL:"))
    }

    @Test func nonIOSRootTabViewDoesNotPresentMangaHost() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/AppEntry/RootTabView.swift")
        let nonIOSBranch = try #require(source.range(of: "#else\n        content"))
        let branchTail = String(source[nonIOSBranch.lowerBound...])
        let branchEnd = try #require(branchTail.range(of: "#endif"))
        let branch = String(branchTail[..<branchEnd.lowerBound])

        #expect(!branch.contains("MangaPresentationHostView"))
        #expect(!branch.contains("activeMangaRoute != nil"))
    }

    @Test func webFallbackViewIsIOSOnly() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/WebFallback/MangaWebFallbackView.swift")

        #expect(source.contains("#if os(iOS)\npublic struct MangaWebFallbackView"))
    }

    @Test func imagePipelineSourceCachesSuccessesAndDeduplicatesInFlightLoads() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaImagePipeline.swift")

        #expect(source.contains("NSCache<NSString, UIImage>"))
        #expect(source.contains("inFlightContinuations"))
        #expect(source.contains("UIImage(data: data)"))
        #expect(source.contains("MangaImagePipelineError.invalidImageData"))
    }

    @Test func progressImagePreviewUsesPipelineCacheAndLocalizedPageFallback() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        #expect(source.contains("struct MangaReaderProgressImagePreview"))
        #expect(source.contains("MangaReaderProgressPreviewImageArea("))
        #expect(source.contains("MangaReaderProgressPreviewPageLabel("))
        #expect(source.contains("imagePipeline?.cachedImage(for: page)"))
        #expect(source.contains("try await imagePipeline.image(for: page)"))
        #expect(source.contains("catch {"))
        #expect(source.contains("failedPageID = page.id"))
        #expect(source.contains("L10n.string(\"reader.page_number_spaced\", preview.pageNumber)"))
        #expect(source.contains("static let previewSize = CGSize(width: 184, height: 228)"))
        #expect(source.contains("showsPreview: false"))
        #expect(source.contains(".overlay {"))
        #expect(source.contains("if let preview = activeVerticalProgressPreview"))
    }

    @Test func hiddenFailureStackIsNotMeasuredDuringLayout() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")
        let guardRange = try #require(source.range(of: "guard !failureStack.isHidden else"))
        let fittingRange = try #require(source.range(of: "failureStack.systemLayoutSizeFitting(fittingSize)"))
        let hiddenGuardBody = String(source[guardRange.lowerBound..<fittingRange.lowerBound])

        #expect(hiddenGuardBody.contains("failureStack.frame = .zero"))
        #expect(hiddenGuardBody.contains("return"))
        #expect(guardRange.lowerBound < fittingRange.lowerBound)
    }

    @Test func pagedViewportPublishesPageLevelGlobalIndexFromPlan() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("struct MangaPagedReaderViewport: UIViewRepresentable"))
        #expect(source.contains("let plan: MangaPagedReadingPlan"))
        #expect(source.contains("parent.plan.globalIndex(forPageAt: pageIndex)"))
        #expect(source.contains("onCurrentPageChange(globalIndex)"))
        #expect(source.contains("func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)"))
        #expect(!source.contains("MangaPageSpread"))
        #expect(!source.contains("NovelReaderSurface"))
    }

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

private func sourceFile(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
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
