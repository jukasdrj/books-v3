import Foundation
import Combine

/// A lightweight, observable class responsible for prefetching image URLs in the background.
///
/// This class is designed to work with SwiftUI lists to proactively fetch image data
/// and store it in the shared `URLCache`, making subsequent image loads from `AsyncImage`
/// or `CachedAsyncImage` instantaneous.
///
/// ## How It Works
/// 1. **URL Submission:** You provide a list of `URL`s to prefetch.
/// 2. **Background Fetching:** It uses a dedicated `URLSession` with a `.background` QoS
///    to download the image data without blocking the UI.
/// 3. **Caching:** The downloaded data is automatically stored in the shared `URLCache`
///    (if server cache headers permit), which is the standard mechanism used by `URLSession`.
/// 4. **Cancellation:** In-flight prefetch tasks can be cancelled to adapt to fast scrolling
///    or changing view states.
///
/// ## Usage
///
/// ```swift
/// struct MyImageView: View {
///     let url: URL
///     @StateObject private var prefetcher = ImagePrefetcher()
///
///     var body: some View {
///         CachedAsyncImage(url: url)
///             .onAppear {
///                 // Prefetch the next few images
///                 prefetcher.startPrefetching(urls: nextImageURLs)
///             }
///             .onDisappear {
///                 // Cancel prefetching when the view disappears
///                 prefetcher.cancelPrefetching()
///             }
///     }
/// }
/// ```
@MainActor
public final class ImagePrefetcher: ObservableObject {

    private var prefetchTask: Task<Void, Never>?
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: configuration)
    }

    /// Starts prefetching a list of image URLs.
    ///
    /// Any existing prefetch tasks are cancelled before starting a new one.
    /// The fetches are performed on a background thread.
    ///
    /// - Parameter urls: An array of `URL`s to prefetch.
    public func startPrefetching(urls: [URL]) {
        // Cancel any ongoing prefetch task
        cancelPrefetching()

        prefetchTask = Task(priority: .background) {
            for url in urls {
                // Check for cancellation before each fetch
                if Task.isCancelled { return }

                // If the image is already cached, we don't need to fetch it again.
                // URLSession with the default cache policy handles this automatically.
                // A simple dataTask is enough to trigger the cache load.
                do {
                    let (data, _) = try await session.data(from: url)
                    #if DEBUG
                    print("[ImagePrefetcher] Successfully prefetched: \(url.lastPathComponent)")
                    #endif
                    _ = data // Silence unused variable warning
                } catch {
                    #if DEBUG
                    print("[ImagePrefetcher] Failed to prefetch: \(url.lastPathComponent) - \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    /// Cancels the current prefetching task.
    ///
    /// This should be called when the view that triggered the prefetching is no longer
    /// visible, or when the user's scrolling changes the set of images to be prefetched.
    public func cancelPrefetching() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }
}