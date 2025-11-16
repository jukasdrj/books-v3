import SwiftUI

// MARK: - Enrichment Error Toast

/// A toast notification for displaying enrichment errors to users.
///
/// HIG-aligned error messaging with:
/// - Clear visual error indication
/// - Actionable retry option
/// - Dismiss gesture support
///
@available(iOS 26.0, *)
public struct EnrichmentErrorToast: View {
    let errorMessage: String
    @Binding var isPresented: Bool
    @Environment(\.iOS26ThemeStore) private var themeStore
    let onRetry: (() -> Void)?
    
    public init(
        errorMessage: String,
        isPresented: Binding<Bool>,
        onRetry: (() -> Void)? = nil
    ) {
        self.errorMessage = errorMessage
        self._isPresented = isPresented
        self.onRetry = onRetry
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            // Error message with action
            VStack(alignment: .leading, spacing: 2) {
                Text("Enrichment Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                if onRetry != nil {
                    Text("Tap to retry")
                        .font(.caption2)
                        .foregroundStyle(themeStore.primaryColor)
                }
            }
            
            Spacer()
            
            // Dismiss button
            Button {
                withAnimation {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let retry = onRetry {
                retry()
            }
            withAnimation {
                isPresented = false
            }
        }
        .accessibilityLabel("Enrichment error: \(errorMessage)")
        .accessibilityHint("Tap to retry error processing or dismiss this message")
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: isPresented) {
            // Auto-dismiss after 8 seconds. This task is automatically cancelled
            // if the toast is dismissed manually or if the view disappears.
            guard isPresented else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                withAnimation {
                    isPresented = false
                }
            } catch {
                // Task was cancelled, which is expected.
            }
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Enrichment Error Toast") {
    struct PreviewWrapper: View {
        @State private var isShowing = true
        
        var body: some View {
            VStack {
                Color.clear
                
                EnrichmentErrorToast(
                    errorMessage: "Network connection failed. Please check your internet connection and try again.",
                    isPresented: $isShowing
                ) {
                    // Retry action
                    print("Retry tapped")
                }
            }
            .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
        }
    }
    
    return PreviewWrapper()
}