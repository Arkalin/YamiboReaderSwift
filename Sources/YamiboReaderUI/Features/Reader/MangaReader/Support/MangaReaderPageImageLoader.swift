import Foundation
import YamiboReaderCore

#if os(iOS)
import UIKit

enum MangaReaderPageImageLoaderError: Error, Equatable {
    case invalidImageData
}

@MainActor
final class MangaReaderPageImageLoader {
    private let dataLoader: any MangaImageDataLoading
    private let offlineCacheContext: (MangaReaderPageProjection) -> MangaImageOfflineCacheContext?
    private let uiImagePipeline: YamiboUIImagePipeline

    init(
        dataLoader: any MangaImageDataLoading,
        offlineCacheContext: @escaping (MangaReaderPageProjection) -> MangaImageOfflineCacheContext? = { _ in nil },
        uiImagePipeline: YamiboUIImagePipeline = .shared
    ) {
        self.dataLoader = dataLoader
        self.offlineCacheContext = offlineCacheContext
        self.uiImagePipeline = uiImagePipeline
    }

    func cachedImage(for page: MangaReaderPageProjection) -> UIImage? {
        uiImagePipeline.cachedImage(for: page.mangaReaderImageRequest)
    }

    func prefetchImages(for pages: [MangaReaderPageProjection]) {
        for page in pages {
            let request = page.mangaReaderImageRequest
            let offlineContext = offlineCacheContext(page)
            uiImagePipeline.prefetchImage(for: request) { [dataLoader] in
                try await dataLoader.imageData(
                    for: request,
                    offlineCacheContext: offlineContext
                )
            }
        }
    }

    func image(for page: MangaReaderPageProjection) async throws -> UIImage {
        let request = page.mangaReaderImageRequest
        let offlineContext = offlineCacheContext(page)
        do {
            return try await uiImagePipeline.image(for: request) { [dataLoader] in
                try await dataLoader.imageData(
                    for: request,
                    offlineCacheContext: offlineContext
                )
            }
        } catch YamiboUIImagePipelineError.invalidImageData {
            throw MangaReaderPageImageLoaderError.invalidImageData
        }
    }
}

extension MangaReaderPageProjection {
    var mangaReaderImageRequest: YamiboImageRequest {
        YamiboImageRequest(
            url: imageURL,
            refererURL: mangaReaderRefererURL
        )
    }

    var mangaReaderRefererURL: URL {
        YamiboRoute.threadByID(
            tid: sourceIdentity.tid,
            page: sourceIdentity.view,
            authorID: sourceIdentity.authorID,
            reverse: false
        ).url
    }
}
#endif
