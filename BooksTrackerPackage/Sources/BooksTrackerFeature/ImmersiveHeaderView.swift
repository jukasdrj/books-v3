import SwiftUI
import SwiftData

struct ImmersiveHeaderView: View {
    var work: Work

    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        ZStack {
            // MARK: - Immersive Background
            immersiveBackground

            // MARK: - Header Content
            VStack(spacing: 8) {
                Text(work.title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.7), radius: 5, x: 0, y: 2)

                if let authors = work.authors {
                    Text(authors.map { $0.name }.joined(separator: ", "))
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 80) // Adjust for safe area and visual balance
        }
        .frame(height: 300) // Fixed height for the header
    }

    private var immersiveBackground: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred cover art background
                CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 15, opaque: true)
                        .overlay {
                            // Darkening overlay for text contrast
                            Color.black.opacity(0.4)
                        }
                } placeholder: {
                    // Fallback gradient background
                    LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.6),
                            Color.black.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}
