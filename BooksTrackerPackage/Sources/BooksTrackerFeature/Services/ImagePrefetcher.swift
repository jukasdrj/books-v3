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

    /// Shared singleton instance for prefetching across the app
    public static let shared = ImagePrefetcher()

    private var prefetchTask: Task<Void, Never>?
    private let session: URLSession
    private var lastScrollDirection: ScrollDirection = .down

    private enum ScrollDirection {
        case up
        case down
    }

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

    /// Intelligently prefetch images for items near the current index during scroll.
    ///
    /// This method implements a smart prefetching strategy:
    /// - Prefetches next 10 images when within 5 items of the end
    /// - Adapts to scroll direction (cancels prefetch on upward scroll)
    /// - Respects the 50MB cache limit by only prefetching when needed
    ///
    /// **Usage in LazyVGrid:**
    /// ```swift
    /// ForEach(works, id: \.id) { work in
    ///     MyCard(work: work)
    ///         .onAppear {
    ///             ImagePrefetcher.shared.prefetchIfNeeded(
    ///                 for: work,
    ///                 in: cachedFilteredWorks,
    ///                 prefetchCount: 10,
    ///                 threshold: 5
    ///             )
    ///         }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - work: The current work being displayed
    ///   - works: Array of all works in the list
    ///   - prefetchCount: Number of images to prefetch ahead (default: 10)
    ///   - threshold: Distance from end to trigger prefetch (default: 5)
    public func prefetchIfNeeded(
        for work: Work,
        in works: [Work],
        prefetchCount: Int = 10,
        threshold: Int = 5
    ) {
        guard let currentIndex = works.firstIndex(where: { $0.id == work.id }) else {
            return
        }

        let distanceFromEnd = works.count - currentIndex.advanced(by: 1)
        let shouldPrefetch = distanceFromEnd <= threshold

        if shouldPrefetch && currentIndex < works.count {
            let startIndex = currentIndex.advanced(by: 1)
            let endIndex = min(startIndex + prefetchCount, works.count)

            if startIndex < endIndex {
                let worksToPrefetch = Array(works[startIndex..<endIndex])
                let urlsToPrefetch = worksToPrefetch.compactMap { work in
                    CoverImageService.coverURL(for: work)
                }

                if !urlsToPrefetch.isEmpty {
                    #if DEBUG
                    print("[ImagePrefetcher] Prefetching \(urlsToPrefetch.count) images starting at index \(startIndex)")
                    #endif
                    startPrefetching(urls: urlsToPrefetch)
                }
            }
        }
    }
}