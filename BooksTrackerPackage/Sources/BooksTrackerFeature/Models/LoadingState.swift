import Foundation

/// Simple loading state enum for legacy compatibility
/// Use APILoadingState<T> for new code with API error handling
enum LoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}
