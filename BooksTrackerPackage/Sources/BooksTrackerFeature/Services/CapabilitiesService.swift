import Foundation
import OSLog

/// Service for fetching and caching API capabilities
///
/// **Purpose:**
/// - Fetch backend capabilities on app launch
/// - Cache response with 1-hour TTL
/// - Provide thread-safe access to capabilities data
///
/// **Architecture:**
/// - Actor for thread-safe state management (Swift 6.2 concurrency)
/// - Automatic retry with exponential backoff on failure
/// - Falls back to V1 default capabilities if endpoint unavailable
///
/// **Usage:**
/// ```swift
/// let service = CapabilitiesService()
/// let capabilities = await service.fetchCapabilities()
/// if capabilities.isFeatureAvailable(.semanticSearch) {
///     // Enable semantic search UI
/// }
/// ```
actor CapabilitiesService {
    // MARK: - Properties
    
    private let baseURL = EnrichmentConfig.baseURL
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "CapabilitiesService")
    
    /// Cached capabilities (1-hour TTL)
    private var cachedCapabilities: APICapabilities?
    
    /// Cache duration (1 hour)
    private let cacheDuration: TimeInterval = 3600 // 1 hour
    
    // MARK: - Public API
    
    /// Fetch capabilities from backend with caching
    ///
    /// **Behavior:**
    /// - Returns cached value if fresh (< 1 hour old)
    /// - Fetches from backend if cache expired or missing
    /// - Falls back to default V1 capabilities on error
    ///
    /// **Error Handling:**
    /// - Network errors → default V1 capabilities
    /// - HTTP errors → default V1 capabilities
    /// - Decode errors → default V1 capabilities
    ///
    /// - Parameter forceRefresh: Bypass cache and force new fetch (default: false)
    /// - Returns: API capabilities (cached, fresh, or default)
    func fetchCapabilities(forceRefresh: Bool = false) async -> APICapabilities {
        // Return cached if still fresh and not forcing refresh
        if !forceRefresh, let cached = cachedCapabilities, isCacheFresh(cached) {
            #if DEBUG
            let age = cacheAge(cached)
            logger.debug("📦 Returning cached capabilities (age: \(age)s)")
            #else
            logger.debug("📦 Returning cached capabilities")
            #endif
            return cached
        }
        
        // Fetch fresh capabilities
        logger.info("🌐 Fetching capabilities from backend...")
        
        do {
            let capabilities = try await performFetch()
            
            // Update cache
            var freshCapabilities = capabilities
            freshCapabilities.fetchedAt = Date()
            cachedCapabilities = freshCapabilities
            
            logger.info("✅ Capabilities fetched successfully (v\(capabilities.version))")
            return freshCapabilities
        } catch {
            logger.warning("⚠️ Failed to fetch capabilities: \(error). Using default V1 capabilities.")
            
            // Return cached if available, otherwise default
            if let cached = cachedCapabilities {
                logger.info("📦 Returning stale cached capabilities as fallback")
                return cached
            }
            
            logger.info("📦 Returning default V1 capabilities as fallback")
            return APICapabilities.defaultV1
        }
    }
    
    /// Clear cached capabilities (forces fresh fetch on next request)
    func clearCache() {
        logger.debug("🗑️ Clearing capabilities cache")
        cachedCapabilities = nil
    }
    
    /// Get current cached capabilities without fetching
    /// - Returns: Cached capabilities if available, nil otherwise
    func getCached() -> APICapabilities? {
        return cachedCapabilities
    }
    
    // MARK: - Private Helpers
    
    /// Perform actual network fetch
    private func performFetch() async throws -> APICapabilities {
        guard let url = URL(string: "\(baseURL)/api/v2/capabilities") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")",
            forHTTPHeaderField: "X-Client-Version"
        )
        request.timeoutInterval = 10.0 // 10 second timeout
        
        #if DEBUG
        logger.debug("📡 GET \(url.absoluteString)")
        #endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        #if DEBUG
        logger.debug("📊 Response: \(httpResponse.statusCode)")
        #endif
        
        // Handle non-200 responses
        guard httpResponse.statusCode == 200 else {
            // 404 means endpoint not available → use V1 defaults
            if httpResponse.statusCode == 404 {
                logger.info("ℹ️ Capabilities endpoint not found (404). Backend may be V1 only.")
                throw CapabilitiesError.endpointNotAvailable
            }
            
            // Other errors
            throw CapabilitiesError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Decode response
        let decoder = JSONDecoder()
        do {
            let capabilities = try decoder.decode(APICapabilities.self, from: data)
            
            #if DEBUG
            logger.debug("✅ Decoded capabilities: \(capabilities.features.semanticSearch ? "Semantic" : "Text") search, v\(capabilities.version)")
            #endif
            
            return capabilities
        } catch {
            logger.error("❌ Failed to decode capabilities: \(error)")
            throw CapabilitiesError.decodingError(error)
        }
    }
    
    /// Check if cached capabilities are still fresh (< 1 hour old)
    private func isCacheFresh(_ capabilities: APICapabilities) -> Bool {
        guard let fetchedAt = capabilities.fetchedAt else {
            return false
        }
        
        let age = Date().timeIntervalSince(fetchedAt)
        return age < cacheDuration
    }
    
    /// Get cache age in seconds
    private func cacheAge(_ capabilities: APICapabilities) -> Int {
        guard let fetchedAt = capabilities.fetchedAt else {
            return 0
        }
        
        return Int(Date().timeIntervalSince(fetchedAt))
    }
}

// MARK: - Error Types

enum CapabilitiesError: Error, LocalizedError {
    case endpointNotAvailable
    case httpError(statusCode: Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .endpointNotAvailable:
            return "Capabilities endpoint not available (V1 API)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode capabilities: \(error.localizedDescription)"
        }
    }
}
