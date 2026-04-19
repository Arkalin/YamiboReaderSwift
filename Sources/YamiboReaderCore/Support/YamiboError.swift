import Foundation

public enum YamiboError: LocalizedError, Equatable, Sendable {
    case invalidResponse(statusCode: Int?)
    case unreadableBody
    case emptyHTML
    case parsingFailed(context: String)
    case floodControl
    case notAuthenticated
    case offline
    case searchCooldown(seconds: Int)
    case persistenceFailed(String)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode):
            if let statusCode {
                return "论坛响应异常（HTTP \(statusCode)）"
            }
            return "未拿到有效的论坛响应"
        case .unreadableBody:
            return "响应内容无法解析为文本"
        case .emptyHTML:
            return "返回内容为空"
        case let .parsingFailed(context):
            return "页面解析失败：\(context)"
        case .floodControl:
            return "论坛触发了防灌水限制，请稍后再试"
        case .notAuthenticated:
            return "当前登录态不可用，请重新登录"
        case .offline:
            return "当前网络不可用，且本地没有可读缓存"
        case let .searchCooldown(seconds):
            return "搜索冷却中，请等待\(seconds)秒"
        case let .persistenceFailed(message):
            return "本地数据保存失败：\(message)"
        case let .underlying(message):
            return message
        }
    }
}
