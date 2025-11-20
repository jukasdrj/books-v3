import Foundation

public struct APIError: Error, LocalizedError {
    public let code: String
    public let message: String

    public var errorDescription: String? {
        "\(message) (Code: \(code))"
    }
}
