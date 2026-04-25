import Foundation

public enum YamiboError: LocalizedError, Equatable, Sendable {
    case invalidResponse(statusCode: Int?)
    case unreadableBody
    case emptyHTML
    case parsingFailed(context: String)
    case floodControl
    case notAuthenticated
    case accountUIDUnavailable
    case offline
    case searchCooldown(seconds: Int)
    case persistenceFailed(String)
    case missingFavoriteDeleteToken
    case missingFavoriteDeleteID
    case favoriteDeleteFailed
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode):
            if let statusCode {
                return L10n.string("error.invalid_response_with_status", statusCode)
            }
            return L10n.string("error.invalid_response")
        case .unreadableBody:
            return L10n.string("error.unreadable_body")
        case .emptyHTML:
            return L10n.string("error.empty_html")
        case let .parsingFailed(context):
            return L10n.string("error.parsing_failed", context)
        case .floodControl:
            return L10n.string("error.flood_control")
        case .notAuthenticated:
            return L10n.string("error.not_authenticated")
        case .accountUIDUnavailable:
            return L10n.string("error.account_uid_unavailable")
        case .offline:
            return L10n.string("error.offline")
        case let .searchCooldown(seconds):
            return L10n.string("error.search_cooldown", seconds)
        case let .persistenceFailed(message):
            return L10n.string("error.persistence_failed", message)
        case .missingFavoriteDeleteToken:
            return L10n.string("error.missing_favorite_delete_token")
        case .missingFavoriteDeleteID:
            return L10n.string("error.missing_favorite_delete_id")
        case .favoriteDeleteFailed:
            return L10n.string("error.favorite_delete_failed")
        case let .underlying(message):
            return message
        }
    }
}
