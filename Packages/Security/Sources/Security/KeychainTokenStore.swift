import Foundation
#if canImport(Security)
import Security
#endif

public struct TokenPair: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public enum KeychainTokenStoreError: Error, Equatable, Sendable {
    case invalidService
    case encodingFailed
    case decodingFailed
    case keychainUnavailable
    case keychainFailure
}

public protocol TokenStore: Sendable {
    func save(_ tokens: TokenPair) throws
    func load() throws -> TokenPair?
    func clear() throws
}

/// Stores the token pair as one Keychain item. Updating one item keeps replacement
/// atomic from the app's perspective and avoids ever persisting tokens in preferences.
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.learning-superpower.auth", account: String = "token-pair") throws {
        guard !service.isEmpty, !account.isEmpty else { throw KeychainTokenStoreError.invalidService }
        self.service = service
        self.account = account
    }

    public func save(_ tokens: TokenPair) throws {
        guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty else {
            throw KeychainTokenStoreError.encodingFailed
        }
        #if canImport(Security)
        let data: Data
        do { data = try JSONEncoder().encode(tokens) } catch { throw KeychainTokenStoreError.encodingFailed }

        let query = baseQuery()
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainTokenStoreError.keychainFailure }

        var insert = query
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw KeychainTokenStoreError.keychainFailure }
        #else
        throw KeychainTokenStoreError.keychainUnavailable
        #endif
    }

    public func load() throws -> TokenPair? {
        #if canImport(Security)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainTokenStoreError.keychainFailure
        }
        do { return try JSONDecoder().decode(TokenPair.self, from: data) } catch { throw KeychainTokenStoreError.decodingFailed }
        #else
        throw KeychainTokenStoreError.keychainUnavailable
        #endif
    }

    public func clear() throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.keychainFailure
        }
        #else
        throw KeychainTokenStoreError.keychainUnavailable
        #endif
    }

    #if canImport(Security)
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
    #endif
}
