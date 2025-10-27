import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("AIProvider Tests")
struct AIProviderTests {
    @Test("AIProvider enum has Gemini Flash only")
    func testAIProviderCases() throws {
        #expect(AIProvider.allCases.count == 1)
        #expect(AIProvider.allCases.contains(.geminiFlash))
    }

    @Test("Provider has correct raw values")
    func testRawValues() {
        #expect(AIProvider.geminiFlash.rawValue == "gemini-flash")
    }

    @Test("Provider has correct display names")
    func testDisplayNames() {
        #expect(AIProvider.geminiFlash.displayName == "Gemini Flash (Google)")
    }

    @Test("Provider is Codable")
    func testCodable() throws {
        let encoded = try JSONEncoder().encode(AIProvider.geminiFlash)
        let decoded = try JSONDecoder().decode(AIProvider.self, from: encoded)
        #expect(decoded == .geminiFlash)
    }

    @Test("Gemini Flash has detailed description")
    func testDescriptions() {
        #expect(AIProvider.geminiFlash.description.contains("25-40s"))
    }

    @Test("Gemini Flash has correct SF Symbol icon")
    func testIcons() {
        #expect(AIProvider.geminiFlash.icon == "sparkles")
    }

    @Test("Gemini has high-quality preprocessing config")
    func testGeminiPreprocessing() {
        let config = AIProvider.geminiFlash.preprocessingConfig
        #expect(config.maxDimension == 3072)
        #expect(config.jpegQuality == 0.90)
        #expect(config.targetFileSizeKB == 400...600)
    }

    @Test("Gemini Flash persists to UserDefaults")
    func testSettingsPersistence() {
        // Gemini Flash is the only provider now
        let provider = AIProvider.geminiFlash
        #expect(provider.rawValue == "gemini-flash")
        #expect(provider.displayName == "Gemini Flash (Google)")
    }
}
