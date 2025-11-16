import Foundation

struct APIError: Error, LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? {
        "\(message) (Code: \(code))"
    }
}
