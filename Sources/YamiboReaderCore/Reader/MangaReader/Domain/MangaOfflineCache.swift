import Foundation

public struct MangaOfflineCacheMembershipID: Codable, Hashable, Sendable {
    public var ownerName: String
    public var tid: String

    public init(ownerName: String, tid: String) {
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MangaOfflineCacheMembership: Codable, Hashable, Identifiable, Sendable {
    public var ownerName: String
    public var tid: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var imageURLs: [URL]
    public var createdAt: Date

    public var id: MangaOfflineCacheMembershipID {
        MangaOfflineCacheMembershipID(ownerName: ownerName, tid: tid)
    }

    public init(
        ownerName: String,
        tid: String,
        chapterTitle: String,
        chapterURL: URL,
        imageURLs: [URL],
        createdAt: Date = .now
    ) {
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterURL = YamiboRoute.normalizedChapterURL(chapterURL, tid: self.tid)
        self.imageURLs = imageURLs
        self.createdAt = createdAt
    }
}

public struct MangaOfflineCacheOwnerUsage: Codable, Equatable, Sendable {
    public var ownerName: String
    public var byteCount: Int

    public init(ownerName: String, byteCount: Int) {
        self.ownerName = ownerName
        self.byteCount = max(0, byteCount)
    }
}

public enum MangaOfflineCacheState: String, Codable, Hashable, Sendable {
    case cached
    case uncached
    case caching
}

public enum MangaOfflineCacheWorkState: String, Codable, Hashable, Sendable {
    case paused
    case failed
}

public enum MangaOfflineCacheQueueRunState: String, Codable, Hashable, Sendable {
    case paused
    case running
}

public struct MangaOfflineCacheWorkRequest: Hashable, Sendable {
    public var ownerName: String
    public var tid: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var targetImageURLs: [URL]

    public init(
        ownerName: String,
        tid: String,
        chapterTitle: String,
        chapterURL: URL,
        targetImageURLs: [URL] = []
    ) {
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterURL = YamiboRoute.normalizedChapterURL(chapterURL, tid: self.tid)
        self.targetImageURLs = Self.uniqueURLs(targetImageURLs)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var output: [URL] = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            output.append(url)
        }
        return output
    }
}

public struct MangaOfflineCacheProgress: Codable, Hashable, Sendable {
    public var completedImageCount: Int
    public var targetImageCount: Int

    public var fractionCompleted: Double {
        guard targetImageCount > 0 else { return 0 }
        return min(1, Double(completedImageCount) / Double(targetImageCount))
    }

    public init(completedImageCount: Int, targetImageCount: Int) {
        self.targetImageCount = max(0, targetImageCount)
        self.completedImageCount = min(max(0, completedImageCount), self.targetImageCount)
    }
}

public struct MangaOfflineCacheWork: Codable, Hashable, Identifiable, Sendable {
    public var ownerName: String
    public var tid: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var targetImageURLs: [URL]
    public var completedImageURLs: [URL]
    public var state: MangaOfflineCacheWorkState
    public var failureMessage: String?
    public var currentBytesPerSecond: Int
    public var insertionIndex: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var id: MangaOfflineCacheMembershipID {
        MangaOfflineCacheMembershipID(ownerName: ownerName, tid: tid)
    }

    public var progress: MangaOfflineCacheProgress {
        MangaOfflineCacheProgress(
            completedImageCount: completedImageURLs.count,
            targetImageCount: targetImageURLs.count
        )
    }

    public init(
        ownerName: String,
        tid: String,
        chapterTitle: String,
        chapterURL: URL,
        targetImageURLs: [URL] = [],
        completedImageURLs: [URL] = [],
        state: MangaOfflineCacheWorkState = .paused,
        failureMessage: String? = nil,
        currentBytesPerSecond: Int = 0,
        insertionIndex: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterURL = YamiboRoute.normalizedChapterURL(chapterURL, tid: self.tid)
        self.targetImageURLs = Self.uniqueURLs(targetImageURLs)
        self.completedImageURLs = Self.uniqueURLs(completedImageURLs)
        self.state = state
        self.failureMessage = failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.failureMessage?.isEmpty == true {
            self.failureMessage = nil
        }
        self.currentBytesPerSecond = max(0, currentBytesPerSecond)
        self.insertionIndex = max(1, insertionIndex)
        self.createdAt = createdAt.mangaOfflineCacheRoundedToSeconds
        self.updatedAt = updatedAt.mangaOfflineCacheRoundedToSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ownerName: try container.decode(String.self, forKey: .ownerName),
            tid: try container.decode(String.self, forKey: .tid),
            chapterTitle: try container.decode(String.self, forKey: .chapterTitle),
            chapterURL: try container.decode(URL.self, forKey: .chapterURL),
            targetImageURLs: try container.decode([URL].self, forKey: .targetImageURLs),
            completedImageURLs: try container.decode([URL].self, forKey: .completedImageURLs),
            state: try container.decode(MangaOfflineCacheWorkState.self, forKey: .state),
            failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
            currentBytesPerSecond: try container.decodeIfPresent(Int.self, forKey: .currentBytesPerSecond) ?? 0,
            insertionIndex: try container.decode(Int.self, forKey: .insertionIndex),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }

    public init(request: MangaOfflineCacheWorkRequest, insertionIndex: Int, now: Date = .now) {
        self.init(
            ownerName: request.ownerName,
            tid: request.tid,
            chapterTitle: request.chapterTitle,
            chapterURL: request.chapterURL,
            targetImageURLs: request.targetImageURLs,
            completedImageURLs: [],
            state: .paused,
            failureMessage: nil,
            currentBytesPerSecond: 0,
            insertionIndex: insertionIndex,
            createdAt: now,
            updatedAt: now
        )
    }

    public func markingFailed(message: String?, at date: Date = .now) -> MangaOfflineCacheWork {
        MangaOfflineCacheWork(
            ownerName: ownerName,
            tid: tid,
            chapterTitle: chapterTitle,
            chapterURL: chapterURL,
            targetImageURLs: targetImageURLs,
            completedImageURLs: completedImageURLs,
            state: .failed,
            failureMessage: message,
            currentBytesPerSecond: 0,
            insertionIndex: insertionIndex,
            createdAt: createdAt,
            updatedAt: date
        )
    }

    public func updatingProgress(
        targetImageURLs: [URL]? = nil,
        completedImageURLs: [URL],
        currentBytesPerSecond: Int? = nil,
        at date: Date = .now
    ) -> MangaOfflineCacheWork {
        MangaOfflineCacheWork(
            ownerName: ownerName,
            tid: tid,
            chapterTitle: chapterTitle,
            chapterURL: chapterURL,
            targetImageURLs: targetImageURLs ?? self.targetImageURLs,
            completedImageURLs: completedImageURLs,
            state: state,
            failureMessage: failureMessage,
            currentBytesPerSecond: currentBytesPerSecond ?? self.currentBytesPerSecond,
            insertionIndex: insertionIndex,
            createdAt: createdAt,
            updatedAt: date
        )
    }

    public func preparingForRun(
        targetImageURLs: [URL]? = nil,
        completedImageURLs: [URL],
        at date: Date = .now
    ) -> MangaOfflineCacheWork {
        MangaOfflineCacheWork(
            ownerName: ownerName,
            tid: tid,
            chapterTitle: chapterTitle,
            chapterURL: chapterURL,
            targetImageURLs: targetImageURLs ?? self.targetImageURLs,
            completedImageURLs: completedImageURLs,
            state: .paused,
            failureMessage: nil,
            currentBytesPerSecond: 0,
            insertionIndex: insertionIndex,
            createdAt: createdAt,
            updatedAt: date
        )
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var output: [URL] = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            output.append(url)
        }
        return output
    }
}

private extension Date {
    var mangaOfflineCacheRoundedToSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}

public enum MangaOfflineCacheEnqueueResult: Hashable, Sendable {
    case alreadyCached(MangaOfflineCacheMembership)
    case alreadyQueued(MangaOfflineCacheWork)
    case enqueued(MangaOfflineCacheWork)

    public var enqueuedWork: MangaOfflineCacheWork? {
        if case let .enqueued(work) = self {
            return work
        }
        return nil
    }
}

public struct MangaOfflineCacheQueueGroup: Hashable, Identifiable, Sendable {
    public var ownerName: String
    public var works: [MangaOfflineCacheWork]

    public var id: String { ownerName }
    public var earliestInsertionIndex: Int {
        works.map(\.insertionIndex).min() ?? .max
    }

    public init(ownerName: String, works: [MangaOfflineCacheWork]) {
        self.ownerName = ownerName
        self.works = works
    }
}

public struct MangaOfflineCacheQueueProjection: Hashable, Sendable {
    public var groups: [MangaOfflineCacheQueueGroup]

    public var unfinishedCount: Int {
        groups.reduce(0) { $0 + $1.works.count }
    }

    public init(groups: [MangaOfflineCacheQueueGroup]) {
        self.groups = groups
    }

    public static func project(
        works: [MangaOfflineCacheWork],
        directoriesByOwnerName: [String: MangaDirectory] = [:]
    ) -> MangaOfflineCacheQueueProjection {
        let grouped = Dictionary(grouping: works, by: \.ownerName)
        let groups = grouped.values.map { ownerWorks in
            let ownerName = ownerWorks[0].ownerName
            let sortedWorks = sortWorks(ownerWorks, directory: directoriesByOwnerName[ownerName])
            return MangaOfflineCacheQueueGroup(ownerName: ownerName, works: sortedWorks)
        }
        .sorted { lhs, rhs in
            if lhs.earliestInsertionIndex != rhs.earliestInsertionIndex {
                return lhs.earliestInsertionIndex < rhs.earliestInsertionIndex
            }
            return lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
        }
        return MangaOfflineCacheQueueProjection(groups: groups)
    }

    private static func sortWorks(
        _ works: [MangaOfflineCacheWork],
        directory: MangaDirectory?
    ) -> [MangaOfflineCacheWork] {
        let directoryOrder = Dictionary(
            uniqueKeysWithValues: (directory?.chapters ?? []).enumerated().map { ($0.element.tid, $0.offset) }
        )

        return works.sorted { lhs, rhs in
            let lhsDirectoryIndex = directoryOrder[lhs.tid]
            let rhsDirectoryIndex = directoryOrder[rhs.tid]
            if let lhsDirectoryIndex, let rhsDirectoryIndex, lhsDirectoryIndex != rhsDirectoryIndex {
                return lhsDirectoryIndex < rhsDirectoryIndex
            }
            if lhsDirectoryIndex != nil, rhsDirectoryIndex == nil {
                return true
            }
            if lhsDirectoryIndex == nil, rhsDirectoryIndex != nil {
                return false
            }
            if lhs.insertionIndex != rhs.insertionIndex {
                return lhs.insertionIndex < rhs.insertionIndex
            }
            return lhs.tid.localizedStandardCompare(rhs.tid) == .orderedAscending
        }
    }
}
