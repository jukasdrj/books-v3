import SwiftUI

private struct BookSearchAPIServiceKey: EnvironmentKey {
    static let defaultValue: BookSearchAPIService? = nil
}

extension EnvironmentValues {
    var bookSearchAPIService: BookSearchAPIService? {
        get { self[BookSearchAPIServiceKey.self] }
        set { self[BookSearchAPIServiceKey.self] = newValue }
    }
}
