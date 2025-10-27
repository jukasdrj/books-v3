import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import BooksTrackerFeature

#if os(iOS)

@Suite("Batch Upload")
struct BatchUploadTests {

    @Test("Compresses images before upload")
    @MainActor
    func imageCompression() async throws {
        let service = await BookshelfAIService.shared
        let largeImage = createLargeTestImage() // 5MB+

        let compressed = try await service.compressImage(largeImage, maxSizeKB: 500)

        let compressedData = compressed.jpegData(compressionQuality: 0.9)!
        #expect(compressedData.count < 600_000) // Under 600KB
    }

    @Test("Creates batch request payload")
    @MainActor
    func batchRequestCreation() async throws {
        let service = await BookshelfAIService.shared

        let image1 = createTestImage()
        let image2 = createTestImage()

        let photos = [
            CapturedPhoto(image: image1),
            CapturedPhoto(image: image2)
        ]

        let jobId = UUID().uuidString
        let request = try await service.createBatchRequest(jobId: jobId, photos: photos)

        #expect(request.jobId == jobId)
        #expect(request.images.count == 2)
        #expect(request.images[0].index == 0)
        #expect(!request.images[0].data.isEmpty)
    }

    @Test("Submits batch to backend", .disabled("Requires live backend"))
    @MainActor
    func batchSubmission() async throws {
        let service = await BookshelfAIService.shared

        let photos = [CapturedPhoto(image: createTestImage())]
        let jobId = UUID().uuidString

        let response = try await service.submitBatch(jobId: jobId, photos: photos)

        #expect(response.jobId == jobId)
        #expect(response.totalPhotos == 1)
        #expect(response.status == "processing")
    }
}

// MARK: - Test Helpers

/// Create a test image (small)
@MainActor
func createTestImage() -> UIImage {
    let size = CGSize(width: 100, height: 100)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        // Add some text to make it realistic
        let text = "Book Spine"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.white
        ]
        text.draw(at: CGPoint(x: 10, y: 40), withAttributes: attributes)
    }
}

/// Create a large test image (5MB+)
@MainActor
func createLargeTestImage() -> UIImage {
    // Create 4K image (3840x2160) to simulate large photo
    let size = CGSize(width: 3840, height: 2160)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        // Fill with gradient to make compression realistic
        let colors = [UIColor.blue, UIColor.green, UIColor.red]
        let height = size.height / CGFloat(colors.count)

        for (index, color) in colors.enumerated() {
            color.setFill()
            let rect = CGRect(x: 0, y: height * CGFloat(index), width: size.width, height: height)
            context.fill(rect)
        }

        // Add noise pattern to simulate real photo
        for _ in 0..<1000 {
            let x = CGFloat.random(in: 0..<size.width)
            let y = CGFloat.random(in: 0..<size.height)
            let noise = CGFloat.random(in: 0...1) > 0.5 ? UIColor.white : UIColor.black
            noise.setFill()
            context.fill(CGRect(x: x, y: y, width: 2, height: 2))
        }
    }
}

#endif // os(iOS)
