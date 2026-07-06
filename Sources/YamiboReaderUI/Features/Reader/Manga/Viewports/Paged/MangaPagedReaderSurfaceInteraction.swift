import SwiftUI
import Combine
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaPagedReaderContentIdentity: Equatable {
    var spreadIDs: [String]
    var pageScaleMode: MangaPageScaleMode
    var pagedTurnStyle: ReaderPagedTurnStyle
    var pageTurnDirection: MangaPageTurnDirection
    var pageEdgeFillStyle: MangaPageEdgeFillStyle
    var colorScheme: ColorScheme
}

struct MangaPagedReaderSurfaceInteractionIdentity: Equatable {
    var isChromeVisible: Bool
    var zoomEnabled: Bool
}

struct MangaPagedReaderEdgeRevealRequest {
    let sequence: Int
    let edge: MangaPagedImageSurfaceHorizontalEdge?
}

struct MangaPagedReaderZoomToggleRequest {
    let sequence: Int
    let location: CGPoint?
}

final class MangaPagedReaderPageSurfaceInteraction {
    let edgeRevealRequests = PassthroughSubject<MangaPagedReaderEdgeRevealRequest, Never>()
    let zoomToggleRequests = PassthroughSubject<MangaPagedReaderZoomToggleRequest, Never>()

    private var requestSequence = 0
    private(set) var hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge> = []
    private(set) var isZoomActive = false

    func updateHiddenEdges(_ hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge>) {
        self.hiddenEdges = hiddenEdges
    }

    func updateZoomActive(_ isZoomActive: Bool) {
        self.isZoomActive = isZoomActive
    }

    func hasHiddenContent(onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge) -> Bool {
        hiddenEdges.contains(edge)
    }

    func consumeTap(onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge) -> Bool {
        guard hiddenEdges.contains(edge) else { return false }
        requestSequence += 1
        edgeRevealRequests.send(MangaPagedReaderEdgeRevealRequest(sequence: requestSequence, edge: edge))
        return true
    }

    func requestZoomToggle(at location: CGPoint) {
        requestSequence += 1
        zoomToggleRequests.send(MangaPagedReaderZoomToggleRequest(sequence: requestSequence, location: location))
    }
}

struct MangaPagedReaderSpreadPageSurface {
    let page: MangaReaderPageProjection
    let surfaceIdentity: MangaPagedReaderPageAppearanceIdentity
    let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction
    let onLongPress: (MangaReaderPageProjection) -> Void
}

struct MangaPagedReaderPageAppearanceIdentity: Hashable {
    let pageID: String
    let appearanceGeneration: Int
}
#endif
