import Foundation
import Testing

@testable import SecurityKit

#if canImport(Security)
import Security
#endif

@Suite("KeychainTokenStore")
struct KeychainTokenStoreTests {
    @Test("saves and loads the complete token pair")
    func savesAndLoads() throws {
        #if canImport(Security)
        let store = try makeStore()
        defer { try? store.clear() }
        let expected = makeTokens(access: "access-1", refresh: "refresh-1")

        try store.save(expected)

        #expect(try store.load() == expected)
        #else
        return
        #endif
    }

    @Test("replacement leaves only the newest token pair")
    func replacementIsAtomicFromTheCallersPerspective() throws {
        #if canImport(Security)
        let store = try makeStore()
        defer { try? store.clear() }
        let first = makeTokens(access: "access-1", refresh: "refresh-1")
        let replacement = makeTokens(access: "access-2", refresh: "refresh-2")

        try store.save(first)
        try store.save(replacement)

        #expect(try store.load() == replacement)
        #expect(try matchingItemCount(for: store) == 1)
        #else
        return
        #endif
    }

    @Test("clear removes the token pair")
    func clearRemovesStoredTokens() throws {
        #if canImport(Security)
        let store = try makeStore()
        defer { try? store.clear() }
        try store.save(makeTokens(access: "access", refresh: "refresh"))

        try store.clear()

        #expect(try store.load() == nil)
        #else
        return
        #endif
    }

    @Test("stores credentials with a ThisDeviceOnly accessibility policy")
    func usesThisDeviceOnlyAccessibility() throws {
        let source = try String(contentsOf: keychainSourceURL(), encoding: .utf8)

        #expect(source.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        #expect(!source.contains("kSecAttrAccessibleAfterFirstUnlock\n"))
    }

    @Test("does not reference UserDefaults")
    func doesNotUsePreferencesForTokens() throws {
        let source = try String(contentsOf: keychainSourceURL(), encoding: .utf8)

        #expect(!source.contains("UserDefaults"))
    }

    private func keychainSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Security/KeychainTokenStore.swift")
    }

    private func makeTokens(access: String, refresh: String) -> TokenPair {
        TokenPair(
            accessToken: access,
            refreshToken: refresh,
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    #if canImport(Security)
    private func makeStore() throws -> KeychainTokenStore {
        try KeychainTokenStore(
            service: "com.learning-superpower.tests.\(UUID().uuidString)",
            account: "token-pair"
        )
    }

    private func matchingQuery(for store: KeychainTokenStore) throws -> [String: Any] {
        // The test uses a unique service, so the public token-store identity is enough.
        // The store intentionally keeps these fields private; derive them from its test item.
        let mirror = Mirror(reflecting: store)
        let service = try #require(mirror.children.first { $0.label == "service" }?.value as? String)
        let account = try #require(mirror.children.first { $0.label == "account" }?.value as? String)
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    private func matchingItemCount(for store: KeychainTokenStore) throws -> Int {
        var query = try matchingQuery(for: store)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess)
        return (result as? [[String: Any]])?.count ?? 0
    }
    #endif
}
