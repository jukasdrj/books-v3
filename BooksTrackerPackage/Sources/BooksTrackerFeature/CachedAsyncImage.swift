import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit

// MARK: - Image Cache Manager

/// Shared image cache manager - handles the static cache limitation in generic types
// SAFETY: @unchecked Sendable because NSCache is thread-safe and DispatchQueue provides
// proper synchronization for all operations. Singleton pattern ensures controlled access.
public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()

    /// Shared NSCache instance with intelligent memory management
    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100 // Maximum 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        return cache
    }()

    private let cacheQueue = DispatchQueue(label: "image-cache", attributes: .concurrent)

    private init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        clearCache()
    }

    public func getImage(for key: String) -> UIImage? {
        return cacheQueue.sync {
            imageCache.object(forKey: NSString(string: key))
        }
    }

    public func setImage(_ image: UIImage, for key: String, cost: Int) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.imageCache.setObject(image, forKey: NSString(string: key), cost: cost)
        }
    }

    public func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.imageCache.removeAllObjects()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Cached Async Image

/// Advanced async image loading with NSCache-based caching to eliminate flickering
/// and reduce network usage. Replaces standard AsyncImage throughout the app.
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var imageState: ImageState = .loading

    private enum ImageState: Equatable {
        case loading
        case loaded(UIImage)
        case failed

        static func == (lhs: ImageState, rhs: ImageState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed):
                return true
            case (.loaded(let lhsImage), (.loaded(let rhsImage))):
                return lhsImage === rhsImage
            default:
                return false
            }
        }
    }

    // MARK: - Initializers

    public init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            switch imageState {
            case .loading:
                placeholder()
                    .transition(.opacity)

            case .loaded(let uiImage):
                content(Image(uiImage: uiImage))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .failed:
                placeholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: imageState)
        .task(id: url) {
            await loadImage()
        }
    }

    // MARK: - Image Loading Logic

    @MainActor
    private func loadImage() async {
        guard let url = url else {
            imageState = .failed
            return
        }

        let cacheKey = url.absoluteString

        // Check cache first
        if let cachedImage = ImageCacheManager.shared.getImage(for: cacheKey) {
            withTransaction(transaction) {
                imageState = .loaded(cachedImage)
            }
            return
        }

        // Set loading state if not cached
        withTransaction(transaction) {
            imageState = .loading
        }

        do {
            // Download image
            let (data, response) = try await URLSession.shared.data(from: url)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let uiImage = UIImage(data: data) else {
                withTransaction(transaction) {
                    imageState = .failed
                }
                return
            }

            // Cache the image with cost calculation
            let imageCost = data.count
            ImageCacheManager.shared.setImage(uiImage, for: cacheKey, cost: imageCost)

            // Update UI on main thread
            withTransaction(transaction) {
                imageState = .loaded(uiImage)
            }

        } catch {
            withTransaction(transaction) {
                imageState = .failed
            }
        }
    }
}

// MARK: - Convenience Initializers

public extension CachedAsyncImage where Content == Image {
    /// Simple initializer when content is just an Image
    init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            scale: scale,
            transaction: transaction,
            content: { $0 },
            placeholder: placeholder
        )
    }
}

public extension CachedAsyncImage where Placeholder == Color {
    /// Initializer with Color placeholder
    init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            scale: scale,
            transaction: transaction,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

public extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Simplest initializer
    init(url: URL?, scale: CGFloat = 1.0) {
        self.init(
            url: url,
            scale: scale,
            transaction: Transaction(),
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - Preview Support

@available(iOS 26.0, *)
#Preview("Cached Async Image") {
    VStack(spacing: 20) {
        // Example with book cover URL
        CachedAsyncImage(
            url: URL(string: "https://covers.openlibrary.org/b/id/8225261-L.jpg")
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay {
                    VStack {
                        Image(systemName: "book.closed")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .frame(width: 120, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        // Example with simple placeholder
        CachedAsyncImage(url: URL(string: "https://example.com/invalid-image.jpg")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(.gray.opacity(0.3))
                .overlay {
                    Text("No Image")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 100, height: 100)

        Button("Clear Cache") {
            ImageCacheManager.shared.clearCache()
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}

#endif
