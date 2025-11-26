import SwiftUI
import SwiftData

/// Coordinator for handling ISBN barcode scans with V2 enrichment
/// Wraps ISBNScannerView and shows QuickAddBookView after successful enrichment
@MainActor
@available(iOS 26.0, *)
public struct ISBNScannerCoordinator: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingScanner = true
    @State private var showingQuickAdd = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isEnriching = false
    @State private var enrichmentResponse: V2EnrichmentResponse?
    
    private let enrichmentService = EnrichmentService.shared
    
    public init() {}
    
    public var body: some View {
        Group {
            if showingScanner {
                ISBNScannerView { isbn in
                    handleScannedISBN(isbn)
                }
            } else if isEnriching {
                enrichingView
            } else if let response = enrichmentResponse, showingQuickAdd {
                QuickAddBookView(enrichmentResponse: response)
            }
        }
        .alert("Enrichment Error", isPresented: $showingError) {
            Button("Try Again") {
                showingScanner = true
                showingError = false
            }
            Button("Cancel", role: .cancel) {
                // Will dismiss the coordinator
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var enrichingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Looking up book...")
                .font(.headline)
            
            Text("Searching book databases")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private func handleScannedISBN(_ isbn: ISBNValidator.ISBN) {
        showingScanner = false
        isEnriching = true
        
        Task {
            do {
                // Use V2 enrichment endpoint for fast, synchronous lookup
                let apiClient = EnrichmentAPIClient()
                let response = try await apiClient.enrichBookV2(barcode: isbn.normalizedValue)
                
                #if DEBUG
                print("✅ V2 Enrichment successful: \(response.title)")
                #endif
                
                // Show quick add view with enriched data
                enrichmentResponse = response
                isEnriching = false
                showingQuickAdd = true
                
            } catch let error as EnrichmentV2Error {
                handleEnrichmentError(error)
            } catch {
                errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                isEnriching = false
                showingError = true
            }
        }
    }
    
    private func handleEnrichmentError(_ error: EnrichmentV2Error) {
        isEnriching = false
        
        switch error {
        case .bookNotFound(let message, let providers):
            if providers.isEmpty {
                errorMessage = message
            } else {
                errorMessage = "\(message)\n\nProviders checked: \(providers.joined(separator: ", "))"
            }
            
        case .rateLimitExceeded(let retryAfter, let message):
            let minutes = retryAfter / 60
            if minutes > 0 {
                errorMessage = "\(message)\n\nPlease try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
            } else {
                errorMessage = "\(message)\n\nPlease try again in \(retryAfter) seconds."
            }
            
        case .serviceUnavailable(let message):
            errorMessage = "\(message)\n\nPlease try again later."
            
        case .invalidBarcode(let barcode):
            errorMessage = "Invalid ISBN format: \(barcode)\n\nPlease scan a valid ISBN-10 or ISBN-13 barcode."
            
        case .invalidResponse:
            errorMessage = "Received an invalid response from the server.\n\nPlease try again."
            
        case .httpError(let statusCode):
            errorMessage = "Server error (HTTP \(statusCode))\n\nPlease try again later."
        }
        
        showingError = true
    }
}
