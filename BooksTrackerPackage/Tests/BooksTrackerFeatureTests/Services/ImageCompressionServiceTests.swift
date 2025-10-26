import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import BooksTrackerFeature

@Suite("ImageCompressionService")
struct ImageCompressionServiceTests {

    #if canImport(UIKit)
    @Test("compress returns data within size limit")
    func testCompressReturnsSizeLimit() throws {
        let service = ImageCompressionService()
        let image = createMockImage(size: CGSize(width: 4000, height: 3000))

        let maxSize = 1_000_000 // 1MB
        let compressed = service.compress(image, maxSizeBytes: maxSize)

        #expect(compressed != nil, "Compression should succeed")
        #expect(compressed!.count <= maxSize, "Compressed data should be within size limit")
    }

    @Test("compress preserves image quality within constraints")
    func testCompressPreservesQuality() throws {
        let service = ImageCompressionService()
        let image = createMockImage(size: CGSize(width: 2000, height: 1500))

        let compressed = service.compress(image, maxSizeBytes: 500_000)

        #expect(compressed != nil, "Compression should succeed")

        // Verify we can recreate image from data
        let recreated = UIImage(data: compressed!)
        #expect(recreated != nil, "Should be able to recreate image from compressed data")
    }

    @Test("compress handles extremely large images")
    func testCompressHandlesLargeImages() throws {
        let service = ImageCompressionService()
        let image = createMockImage(size: CGSize(width: 8000, height: 6000))

        let compressed = service.compress(image, maxSizeBytes: 2_000_000)

        #expect(compressed != nil, "Should compress even very large images")
        #expect(compressed!.count <= 2_000_000)
    }

    // MARK: - Helpers

    private func createMockImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    #endif
}
