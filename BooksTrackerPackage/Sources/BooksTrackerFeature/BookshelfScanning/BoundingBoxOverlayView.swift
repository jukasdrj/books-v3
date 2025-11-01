import SwiftUI

#if canImport(UIKit)

@available(iOS 26.0, *)
struct BoundingBoxOverlayView: View {
    let image: UIImage
    let detectedBooks: [DetectedBook]

    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0

    @State private var currentOffset = CGSize.zero
    @State private var finalOffset = CGSize.zero

    var body: some View {
        let dragGesture = DragGesture()
            .onChanged { value in
                self.currentOffset = CGSize(width: value.translation.width + self.finalOffset.width, height: value.translation.height + self.finalOffset.height)
            }
            .onEnded { value in
                self.finalOffset = self.currentOffset
            }

        let magnificationGesture = MagnificationGesture()
            .onChanged { value in
                self.currentScale = value * self.finalScale
            }
            .onEnded { value in
                self.finalScale = self.currentScale
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
                        .stroke(self.color(for: book.confidence), lineWidth: 2 / self.currentScale)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel(self.accessibilityLabel(for: book))
                }
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .scaleEffect(self.currentScale)
            .offset(self.currentOffset)
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
        var label = ""
        if let title = book.title { label += title } else { label += "Unknown title" }
        if let author = book.author { label += " by \(author)" }
        let confidencePercent = Int(book.confidence * 100)
        label += ". Confidence: \(confidencePercent)%."
        if book.confidence >= 0.7 { label += " Detected." }
        else if book.confidence >= 0.1 { label += " Uncertain." }
        else { label += " Unreadable." }
        return label
    }

    private func color(for confidence: Double) -> Color {
        if confidence >= 0.7 {
            return .green
        } else if confidence >= 0.1 {
            return .yellow
        } else {
            return .red
        }
    }
}

#endif
