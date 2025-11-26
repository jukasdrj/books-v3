import Foundation

/// Generic loading state for async operations
enum LoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}
