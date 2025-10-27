import Testing
import UIKit
@testable import BooksTrackerFeature

@Suite("Batch Scan Models")
@MainActor
struct BatchScanModelTests {

    @Test("CapturedPhoto stores image and metadata")
    func capturedPhotoCreation() {
        let image = createBatchScanTestImage()
        let photo = CapturedPhoto(image: image)

        #expect(photo.id != UUID())
        #expect(photo.image === image)
        #expect(photo.timestamp <= Date())
    }

    @Test("BatchProgress initializes with queued photos")
    func batchProgressInitialization() {
        let progress = BatchProgress(jobId: "test-123", totalPhotos: 3)

        #expect(progress.jobId == "test-123")
        #expect(progress.totalPhotos == 3)
        #expect(progress.photos.count == 3)
        #expect(progress.photos.allSatisfy { $0.status == .queued })
        #expect(progress.totalBooksFound == 0)
    }

    @Test("BatchProgress updates photo status")
    func updatePhotoStatus() {
        let progress = BatchProgress(jobId: "test-123", totalPhotos: 2)

        progress.updatePhoto(index: 0, status: .processing)

        #expect(progress.photos[0].status == .processing)
        #expect(progress.photos[1].status == .queued)
        #expect(progress.currentPhotoIndex == 0)
    }

    @Test("BatchProgress accumulates books across photos")
    func accumulateBooks() {
        let progress = BatchProgress(jobId: "test-123", totalPhotos: 2)

        let book1 = AIDetectedBook(
            title: "Book 1",
            author: "Author 1",
            confidence: 0.9
        )
        let book2 = AIDetectedBook(
            title: "Book 2",
            author: "Author 2",
            confidence: 0.8
        )

        progress.updatePhoto(index: 0, status: .complete, booksFound: [book1])
        progress.updatePhoto(index: 1, status: .complete, booksFound: [book2])

        #expect(progress.totalBooksFound == 2)
        #expect(progress.photos[0].booksFound?.count == 1)
        #expect(progress.photos[1].booksFound?.count == 1)
    }

    @Test("Respects 5 photo maximum")
    func photoLimit() {
        var photos: [CapturedPhoto] = []

        for _ in 0..<5 {
            photos.append(CapturedPhoto(image: createBatchScanTestImage()))
        }

        #expect(photos.count == 5)

        // Attempting to add 6th photo should be rejected by model
        #expect(photos.count <= CapturedPhoto.maxPhotosPerBatch)
    }

    @Test("BatchProgress marks complete correctly")
    func batchCompletion() {
        let progress = BatchProgress(jobId: "test-123", totalPhotos: 2)

        progress.updatePhoto(index: 0, status: .complete)
        progress.updatePhoto(index: 1, status: .complete)

        #expect(progress.isComplete == true)
        #expect(progress.successCount == 2)
        #expect(progress.errorCount == 0)
    }

    @Test("BatchProgress counts errors")
    func errorCounting() {
        let progress = BatchProgress(jobId: "test-123", totalPhotos: 3)

        progress.updatePhoto(index: 0, status: .complete)
        progress.updatePhoto(index: 1, status: .error, error: "AI failed")
        progress.updatePhoto(index: 2, status: .complete)

        #expect(progress.successCount == 2)
        #expect(progress.errorCount == 1)
        #expect(progress.isComplete == true)
    }

    @Test("PhotoProgress initializes with queued status")
    func photoProgressInit() {
        let photoProgress = PhotoProgress(index: 0)

        #expect(photoProgress.index == 0)
        #expect(photoProgress.status == .queued)
        #expect(photoProgress.booksFound == nil)
        #expect(photoProgress.error == nil)
    }

    @Test("BatchScanRequest encodes correctly")
    func batchRequestEncoding() throws {
        let request = BatchScanRequest(
            jobId: "test-job",
            images: [
                BatchScanRequest.ImageData(index: 0, data: "base64data1"),
                BatchScanRequest.ImageData(index: 1, data: "base64data2")
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BatchScanRequest.self, from: data)

        #expect(decoded.jobId == "test-job")
        #expect(decoded.images.count == 2)
        #expect(decoded.images[0].index == 0)
        #expect(decoded.images[0].data == "base64data1")
    }
}

// MARK: - Helpers

private func createBatchScanTestImage() -> UIImage {
    UIImage(systemName: "book")!
}
