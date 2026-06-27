import Foundation

public enum ReaderResumeRoute: Codable, Hashable, Sendable {
    case novel(ReaderLaunchContext)
    case manga(MangaPresentationRoute)

    private enum CodingKeys: String, CodingKey {
        case kind
        case novelContext
        case mangaRoute
    }

    private enum Kind: String, Codable {
        case novel
        case manga
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .novel(context):
            try container.encode(Kind.novel, forKey: .kind)
            try container.encode(context, forKey: .novelContext)
        case let .manga(route):
            try container.encode(Kind.manga, forKey: .kind)
            try container.encode(route, forKey: .mangaRoute)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .novel:
            self = .novel(try container.decode(ReaderLaunchContext.self, forKey: .novelContext))
        case .manga:
            self = .manga(try container.decode(MangaPresentationRoute.self, forKey: .mangaRoute))
        }
    }
}
