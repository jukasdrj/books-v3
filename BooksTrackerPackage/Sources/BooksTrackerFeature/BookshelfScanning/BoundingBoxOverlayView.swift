import SwiftUI

#if canImport(UIKit)

@available(iOS 26.0, *)
struct BoundingBoxOverlayView: View {
    let image: UIImage
    let detectedBooks: [DetectedBook]

    @State private var finalScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    @State private var finalOffset = CGSize.zero
    @GestureState private var gestureOffset = CGSize.zero

    // MARK: - Confidence Thresholds

    private enum ConfidenceThreshold {
        static let high: Double = 0.7
        static let medium: Double = 0.1
    }

    var body: some View {
        let dragGesture = DragGesture()
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                self.finalOffset.width += value.translation.width
                self.finalOffset.height += value.translation.height
            }

        let magnificationGesture = MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                self.finalScale *= value
            }

        let combinedGesture = dragGesture.simultaneously(with: magnificationGesture)

        GeometryReader { geometry in
            let imageFrame = calculateImageFrame(in: geometry.size, imageSize: image.size)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                ForEach(detectedBooks) { book in
                    let rect = self.convert(normalizedRect: book.boundingBox, to: imageFrame.size)
                    Rectangle()
                        .stroke(self.color(for: book.confidence), lineWidth: 2 / (self.finalScale * self.gestureScale))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel(self.accessibilityLabel(for: book))
                }
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .scaleEffect(self.finalScale * self.gestureScale)
            .offset(x: self.finalOffset.width + self.gestureOffset.width, y: self.finalOffset.height + self.gestureOffset.height)
            .gesture(combinedGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Scanned photo of bookshelf with \(detectedBooks.count) detected books.")
        }
    }

    private func calculateImageFrame(in containerSize: CGSize, imageSize: CGSize) -> CGRect {
        let containerAspectRatio = containerSize.width / containerSize.height
        let imageAspectRatio = imageSize.width / imageSize.height
        var newSize = containerSize
        var origin = CGPoint.zero
        if containerAspectRatio > imageAspectRatio {
            newSize.width = containerSize.height * imageAspectRatio
            origin.x = (containerSize.width - newSize.width) / 2
        } else {
            newSize.height = containerSize.width / imageAspectRatio
            origin.y = (containerSize.height - newSize.height) / 2
        }
        return CGRect(origin: origin, size: newSize)
    }

    private func convert(normalizedRect: CGRect, to imageSize: CGSize) -> CGRect {
        let scale = CGAffineTransform.identity.scaledBy(x: imageSize.width, y: imageSize.height)
        return normalizedRect.applying(scale)
    }

    private func accessibilityLabel(for book: DetectedBook) -> String {
        let titlePart = book.title ?? "Unknown title"
        let authorPart = book.author.map { " by \($0)" } ?? ""
        let confidencePercent = Int(book.confidence * 100)

        let confidenceDescription: String
        if book.confidence >= ConfidenceThreshold.high {
            confidenceDescription = "Detected."
        } else if book.confidence >= ConfidenceThreshold.medium {
            confidenceDescription = "Uncertain."
        } else {
            confidenceDescription = "Unreadable."
        }

        return "\(titlePart)\(authorPart). Confidence: \(confidencePercent)%. \(confidenceDescription)"
    }

    private func color(for confidence: Double) -> Color {
        if confidence >= ConfidenceThreshold.high {
            return .green
        } else if confidence >= ConfidenceThreshold.medium {
            return .yellow
        } else {
            return .red
        }
    }
}

#endif
