import SwiftUI

/// Loading state representation for async data operations with API error support
///
/// Represents the four common states of data loading:
/// - idle: Initial state, nothing loaded yet
/// - loading: Data is being fetched
/// - success: Data loaded successfully
/// - error: An error occurred during loading
enum APILoadingState<T> {
    case idle
    case loading
    case success(T)
    case error(ApiErrorInfo)
}

/// Generic loading state view wrapper with API error support
///
/// Manages display of loading, success, and error states with consistent UI.
/// Part of Phase 2, Task 4 of V3 Migration Plan.
///
/// Usage:
/// ```swift
/// APILoadingStateView(state: viewModel.loadingState, retryAction: viewModel.retry) { books in
///     List(books) { book in
///         BookRow(book: book)
///     }
/// }
/// ```
struct APILoadingStateView<Content: View, T>: View {
    let state: APILoadingState<T>
    let retryAction: (() -> Void)?
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .idle:
            Text("Ready")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading content")
        case .success(let data):
            content(data)
        case .error(let error):
            ErrorView(error: error, retryAction: retryAction)
        }
    }
}

// MARK: - Previews

#Preview("API Loading State") {
    struct PreviewWrapper: View {
        @State private var currentState: APILoadingState<[String]> = .idle

        var body: some View {
            VStack {
                APILoadingStateView(state: currentState, retryAction: retry) { books in
                    List(books, id: \.self) { book in
                        Text(book)
                    }
                }
                .frame(height: 300)
                .border(Color.gray.opacity(0.3))

                Spacer()

                // State controls
                HStack {
                    Button("Idle") { currentState = .idle }
                    Button("Loading") { currentState = .loading }
                    Button("Success") {
                        currentState = .success([
                            "The Great Gatsby",
                            "To Kill a Mockingbird",
                            "1984"
                        ])
                    }
                    Button("Error") {
                        currentState = .error(ApiErrorInfo(
                            message: "Network failed",
                            code: "NETWORK_ERROR",
                            details: nil,
                            statusCode: nil,
                            retryable: true
                        ))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }

        func retry() {
            currentState = .loading
            // Simulate network request
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                currentState = .success(["Retried successfully!"])
            }
        }
    }

    return PreviewWrapper()
}
