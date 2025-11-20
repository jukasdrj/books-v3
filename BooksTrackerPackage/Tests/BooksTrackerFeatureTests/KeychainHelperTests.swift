import Testing
import Foundation
import Security
@testable import BooksTrackerFeature

@Suite("KeychainHelper Tests", .serialized)
struct KeychainHelperTests {

    // MARK: - Test Constants

    private static let testToken = "test-token-12345"
    private static let testService = "com.oooefam.booksV3.websocket"

    // Generate unique account for each test
    private var testAccount: String { "test-account-\(UUID().uuidString)" }
    
    // MARK: - Save Token Tests
    
    @Test("Save token successfully stores token in keychain")
    func testSaveTokenSuccess() throws {
        // Given
        let account = testAccount
        let token = Self.testToken
        
        // When
        try KeychainHelper.saveToken(token, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == token)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Save token overwrites existing token")
    func testSaveTokenOverwrite() throws {
        // Given
        let account = testAccount
        let originalToken = "original-token"
        let newToken = "new-token"
        
        // When - Save original token
        try KeychainHelper.saveToken(originalToken, for: account)
        
        // Then - Verify original token is saved
        let retrievedOriginal = try KeychainHelper.getToken(for: account)
        #expect(retrievedOriginal == originalToken)
        
        // When - Overwrite with new token
        try KeychainHelper.saveToken(newToken, for: account)
        
        // Then - Verify new token overwrites original
        let retrievedNew = try KeychainHelper.getToken(for: account)
        #expect(retrievedNew == newToken)
        #expect(retrievedNew != originalToken)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Save empty token stores empty string")
    func testSaveEmptyToken() throws {
        // Given
        let account = testAccount
        let emptyToken = ""
        
        // When
        try KeychainHelper.saveToken(emptyToken, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == emptyToken)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Save token with special characters")
    func testSaveTokenWithSpecialCharacters() throws {
        // Given
        let account = testAccount
        let specialToken = "token-with-special-chars!@#$%^&*()_+-=[]{}|;':\",./<>?"
        
        // When
        try KeychainHelper.saveToken(specialToken, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == specialToken)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Save token with unicode characters")
    func testSaveTokenWithUnicode() throws {
        // Given
        let account = testAccount
        let unicodeToken = "token-with-unicode-🔐🔑🛡️-测试-🎯"
        
        // When
        try KeychainHelper.saveToken(unicodeToken, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == unicodeToken)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Save token with empty account identifier")
    func testSaveTokenEmptyAccount() throws {
        // Given
        let emptyAccount = ""
        let token = Self.testToken
        
        // When
        try KeychainHelper.saveToken(token, for: emptyAccount)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: emptyAccount)
        #expect(retrievedToken == token)
        
        // Cleanup
        KeychainHelper.deleteToken(for: emptyAccount)
    }
    
    // MARK: - Get Token Tests
    
    @Test("Get token returns nil for non-existent account")
    func testGetTokenNonExistent() throws {
        // Given
        let nonExistentAccount = "non-existent-account-\(UUID().uuidString)"
        
        // When
        let retrievedToken = try KeychainHelper.getToken(for: nonExistentAccount)
        
        // Then
        #expect(retrievedToken == nil)
    }
    
    @Test("Get token returns correct token for existing account")
    func testGetTokenExisting() throws {
        // Given
        let account = testAccount
        let token = Self.testToken
        
        // Setup - Save token first
        try KeychainHelper.saveToken(token, for: account)
        
        // When
        let retrievedToken = try KeychainHelper.getToken(for: account)
        
        // Then
        #expect(retrievedToken == token)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Get token with empty account identifier")
    func testGetTokenEmptyAccount() throws {
        // Given
        let emptyAccount = ""
        let token = Self.testToken
        
        // Setup - Save token first
        try KeychainHelper.saveToken(token, for: emptyAccount)
        
        // When
        let retrievedToken = try KeychainHelper.getToken(for: emptyAccount)
        
        // Then
        #expect(retrievedToken == token)
        
        // Cleanup
        KeychainHelper.deleteToken(for: emptyAccount)
    }
    
    // MARK: - Delete Token Tests
    
    @Test("Delete token removes token from keychain")
    func testDeleteToken() throws {
        // Given
        let account = testAccount
        let token = Self.testToken
        
        // Setup - Save token first
        try KeychainHelper.saveToken(token, for: account)
        
        // Verify token exists
        let retrievedBeforeDelete = try KeychainHelper.getToken(for: account)
        #expect(retrievedBeforeDelete == token)
        
        // When
        KeychainHelper.deleteToken(for: account)
        
        // Then
        let retrievedAfterDelete = try KeychainHelper.getToken(for: account)
        #expect(retrievedAfterDelete == nil)
    }
    
    @Test("Delete non-existent token does not throw error")
    func testDeleteNonExistentToken() throws {
        // Given
        let nonExistentAccount = "non-existent-account-\(UUID().uuidString)"
        
        // When/Then - Should not throw
        KeychainHelper.deleteToken(for: nonExistentAccount)

        // Verify still no token
        let token = try KeychainHelper.getToken(for: nonExistentAccount)
        #expect(token == nil)
    }
    
    @Test("Delete token with empty account identifier")
    func testDeleteTokenEmptyAccount() throws {
        // Given
        let emptyAccount = ""
        let token = Self.testToken
        
        // Setup - Save token first
        try KeychainHelper.saveToken(token, for: emptyAccount)
        
        // Verify token exists
        let retrievedBeforeDelete = try KeychainHelper.getToken(for: emptyAccount)
        #expect(retrievedBeforeDelete == token)
        
        // When
        KeychainHelper.deleteToken(for: emptyAccount)
        
        // Then
        let retrievedAfterDelete = try KeychainHelper.getToken(for: emptyAccount)
        #expect(retrievedAfterDelete == nil)
    }
    
    // MARK: - Delete All Tokens Tests
    
    @Test("Delete all tokens removes all tokens for service")
    func testDeleteAllTokens() throws {
        // Given
        let account1 = "test-account-1-\(UUID().uuidString)"
        let account2 = "test-account-2-\(UUID().uuidString)"
        let token1 = "token-1"
        let token2 = "token-2"
        
        // Setup - Save multiple tokens
        try KeychainHelper.saveToken(token1, for: account1)
        try KeychainHelper.saveToken(token2, for: account2)
        
        // Verify tokens exist
        let retrieved1 = try KeychainHelper.getToken(for: account1)
        let retrieved2 = try KeychainHelper.getToken(for: account2)
        #expect(retrieved1 == token1)
        #expect(retrieved2 == token2)
        
        // When
        KeychainHelper.deleteAllTokens()
        
        // Then
        let retrievedAfter1 = try KeychainHelper.getToken(for: account1)
        let retrievedAfter2 = try KeychainHelper.getToken(for: account2)
        #expect(retrievedAfter1 == nil)
        #expect(retrievedAfter2 == nil)
    }
    
    @Test("Delete all tokens when no tokens exist does not throw error")
    func testDeleteAllTokensWhenEmpty() {
        // Given - No tokens exist (cleanup in init ensures this)
        
        // When/Then - Should not throw
        KeychainHelper.deleteAllTokens()
    }
    
    // MARK: - Multiple Account Tests
    
    @Test("Multiple accounts can store different tokens")
    func testMultipleAccounts() throws {
        // Given
        let account1 = "account-1-\(UUID().uuidString)"
        let account2 = "account-2-\(UUID().uuidString)"
        let token1 = "token-for-account-1"
        let token2 = "token-for-account-2"
        
        // When
        try KeychainHelper.saveToken(token1, for: account1)
        try KeychainHelper.saveToken(token2, for: account2)
        
        // Then
        let retrieved1 = try KeychainHelper.getToken(for: account1)
        let retrieved2 = try KeychainHelper.getToken(for: account2)
        
        #expect(retrieved1 == token1)
        #expect(retrieved2 == token2)
        #expect(retrieved1 != retrieved2)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account1)
        KeychainHelper.deleteToken(for: account2)
    }
    
    @Test("Deleting one account does not affect other accounts")
    func testDeleteOneAccountLeavesOthers() throws {
        // Given
        let account1 = "account-1-\(UUID().uuidString)"
        let account2 = "account-2-\(UUID().uuidString)"
        let token1 = "token-for-account-1"
        let token2 = "token-for-account-2"
        
        // Setup
        try KeychainHelper.saveToken(token1, for: account1)
        try KeychainHelper.saveToken(token2, for: account2)
        
        // When - Delete only account1
        KeychainHelper.deleteToken(for: account1)
        
        // Then
        let retrieved1 = try KeychainHelper.getToken(for: account1)
        let retrieved2 = try KeychainHelper.getToken(for: account2)
        
        #expect(retrieved1 == nil)
        #expect(retrieved2 == token2)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account2)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("KeychainError.unexpectedData has correct description")
    func testUnexpectedDataErrorDescription() {
        // Given
        let error = KeychainHelper.KeychainError.unexpectedData
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(description == "Unexpected data format in Keychain")
    }
    
    @Test("KeychainError.unhandledError has correct description")
    func testUnhandledErrorDescription() {
        // Given
        let status: OSStatus = -25300 // errSecItemNotFound
        let error = KeychainHelper.KeychainError.unhandledError(status: status)
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(description == "Keychain error: \(status)")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Very long token can be stored and retrieved")
    func testVeryLongToken() throws {
        // Given
        let account = testAccount
        let longToken = String(repeating: "a", count: 10000) // 10KB token
        
        // When
        try KeychainHelper.saveToken(longToken, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == longToken)
        #expect(retrievedToken?.count == 10000)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Token with newlines and tabs can be stored")
    func testTokenWithWhitespace() throws {
        // Given
        let account = testAccount
        let tokenWithWhitespace = "token\nwith\nnewlines\tand\ttabs\r\nand\rcarriage\rreturns"
        
        // When
        try KeychainHelper.saveToken(tokenWithWhitespace, for: account)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: account)
        #expect(retrievedToken == tokenWithWhitespace)
        
        // Cleanup
        KeychainHelper.deleteToken(for: account)
    }
    
    @Test("Account identifier with special characters")
    func testAccountWithSpecialCharacters() throws {
        // Given
        let specialAccount = "account-with-special!@#$%^&*()_+-=[]{}|;':\",./<>?"
        let token = Self.testToken
        
        // When
        try KeychainHelper.saveToken(token, for: specialAccount)
        
        // Then
        let retrievedToken = try KeychainHelper.getToken(for: specialAccount)
        #expect(retrievedToken == token)
        
        // Cleanup
        KeychainHelper.deleteToken(for: specialAccount)
    }
    
    // MARK: - Integration Tests
    
    @Test("Complete workflow: save, retrieve, update, delete")
    func testCompleteWorkflow() throws {
        // Given
        let account = testAccount
        let originalToken = "original-token"
        let updatedToken = "updated-token"
        
        // When/Then - Save
        try KeychainHelper.saveToken(originalToken, for: account)
        let retrieved1 = try KeychainHelper.getToken(for: account)
        #expect(retrieved1 == originalToken)
        
        // When/Then - Update
        try KeychainHelper.saveToken(updatedToken, for: account)
        let retrieved2 = try KeychainHelper.getToken(for: account)
        #expect(retrieved2 == updatedToken)
        #expect(retrieved2 != originalToken)
        
        // When/Then - Delete
        KeychainHelper.deleteToken(for: account)
        let retrieved3 = try KeychainHelper.getToken(for: account)
        #expect(retrieved3 == nil)
    }
}