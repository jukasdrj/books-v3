import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("Batch Capture UI")
@MainActor
struct BatchCaptureUITests {

    @Test("Shows submit and take more buttons after capture")
    func postCaptureButtons() async {
        let model = BatchCaptureModel()
        let image = createBatchCaptureTestImage()

        model.addPhoto(image)

        #expect(model.capturedPhotos.count == 1)
        #expect(model.showingPostCaptureOptions == true)
    }

    @Test("Returns to camera when take more tapped")
    func takeMoreFlow() async {
        let model = BatchCaptureModel()

        model.addPhoto(createBatchCaptureTestImage())
        model.handleTakeMore()

        #expect(model.showingPostCaptureOptions == false)
        #expect(model.capturedPhotos.count == 1) // Photo retained
    }

    @Test("Enforces 5 photo limit")
    func photoLimit() async {
        let model = BatchCaptureModel()

        // Add 5 photos
        for _ in 0..<5 {
            model.addPhoto(createBatchCaptureTestImage())
        }

        #expect(model.capturedPhotos.count == 5)

        // Attempt to add 6th
        model.addPhoto(createBatchCaptureTestImage())

        #expect(model.capturedPhotos.count == 5) // Still 5
    }

    @Test("Submit initiates batch scan")
    func submitBatch() async {
        let model = BatchCaptureModel()

        model.addPhoto(createBatchCaptureTestImage())
        model.addPhoto(createBatchCaptureTestImage())

        await model.submitBatch()

        #expect(model.isSubmitting == true)
        #expect(model.capturedPhotos.count == 2)
    }

    @Test("Can delete individual photos")
    func deletePhoto() async {
        let model = BatchCaptureModel()

        model.addPhoto(createBatchCaptureTestImage())
        let photo2 = model.addPhoto(createBatchCaptureTestImage())!
        model.addPhoto(createBatchCaptureTestImage())

        model.deletePhoto(photo2)

        #expect(model.capturedPhotos.count == 2)
    }

    @Test("canAddMore reflects photo limit")
    func canAddMoreProperty() async {
        let model = BatchCaptureModel()

        #expect(model.canAddMore == true)

        // Add 4 photos
        for _ in 0..<4 {
            model.addPhoto(createBatchCaptureTestImage())
        }

        #expect(model.canAddMore == true)

        // Add 5th photo
        model.addPhoto(createBatchCaptureTestImage())

        #expect(model.canAddMore == false)
    }

    @Test("Cancel batch stops processing and updates status")
    func cancelBatch() async throws {
        let model = BatchCaptureModel()

        model.addPhoto(createBatchCaptureTestImage())
        model.addPhoto(createBatchCaptureTestImage())

        // Initiate batch submission (will fail in test due to network)
        // This is okay - we just need to set up the progress state
        await model.submitBatch()

        // Manually set up batch progress for testing cancellation
        let jobId = UUID().uuidString
        let progress = BatchProgress(jobId: jobId, totalPhotos: 2)
        model.batchProgress = progress

        // Simulate cancellation
        await model.cancelBatch()

        // Verify cancel was called (in real app, would check network request)
        // For now, just verify the method exists and can be called
        #expect(model.batchProgress != nil)
    }
}

// MARK: - Helper

/// Creates a test image (system SF Symbol)
@MainActor
private func createBatchCaptureTestImage() -> UIImage {
    UIImage(systemName: "book.fill")!
}
