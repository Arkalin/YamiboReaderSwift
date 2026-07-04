import Foundation
import YamiboReaderCore

#if os(iOS)
import UIKit

enum MangaImagePipelineError: Error, Equatable {
    case invalidImageData
}

@MainActor
final class MangaImagePipeline {
    static let defaultMemoryLimitBytes = 80 * 1024 * 1024

    private let dataLoader: any MangaImageDataLoading
    private let offlineCacheContext: (MangaReaderPageProjection) -> MangaImageOfflineCacheContext?
    private let imagePipeline: YamiboImagePipeline

    init(
        dataLoader: any MangaImageDataLoading,
        offlineCacheContext: @escaping (MangaReaderPageProjection) -> MangaImageOfflineCacheContext? = { _ in nil },
        imagePipeline: YamiboImagePipeline = .shared,
        memoryLimitBytes: Int = defaultMemoryLimitBytes
    ) {
        self.dataLoader = dataLoader
        self.offlineCacheContext = offlineCacheContext
        self.imagePipeline = imagePipeline
        _ = memoryLimitBytes
    }

    func cachedImage(for page: MangaReaderPageProjection) -> UIImage? {
        imagePipeline.cachedImage(for: imageRequest(for: page))
    }

    func prefetchImages(for pages: [MangaReaderPageProjection]) {
        for page in pages {
            let imageURL = page.imageURL
            let refererURL = refererURL(for: page)
            let offlineContext = offlineCacheContext(page)
            imagePipeline.prefetchImage(for: imageRequest(for: page)) { [dataLoader] in
                try await dataLoader.imageData(
                    for: imageURL,
                    refererURL: refererURL,
                    offlineCacheContext: offlineContext
                )
            }
        }
    }

    func image(for page: MangaReaderPageProjection) async throws -> UIImage {
        let imageURL = page.imageURL
        let refererURL = refererURL(for: page)
        let offlineContext = offlineCacheContext(page)
        do {
            return try await imagePipeline.image(for: imageRequest(for: page)) { [dataLoader] in
                try await dataLoader.imageData(
                    for: imageURL,
                    refererURL: refererURL,
                    offlineCacheContext: offlineContext
                )
            }
        } catch YamiboImagePipelineError.invalidImageData {
            throw MangaImagePipelineError.invalidImageData
        }
    }

    func imageData(for page: MangaReaderPageProjection) async throws -> Data {
        try await dataLoader.imageData(
            for: page.imageURL,
            refererURL: refererURL(for: page),
            offlineCacheContext: offlineCacheContext(page)
        )
    }

    private func imageRequest(for page: MangaReaderPageProjection) -> YamiboImageRequest {
        YamiboImageRequest(
            url: page.imageURL,
            refererURL: refererURL(for: page)
        )
    }

    private func refererURL(for page: MangaReaderPageProjection) -> URL {
        YamiboRoute.threadByID(
            tid: page.sourceIdentity.tid,
            page: page.sourceIdentity.view,
            authorID: page.sourceIdentity.authorID,
            reverse: false
        ).url
    }
}
#endif
