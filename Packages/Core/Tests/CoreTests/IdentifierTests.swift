import Foundation
import Testing

@testable import Core

private enum UserTag: Sendable {}

@Suite("Identifier")
struct IdentifierTests {
    @Test("preserves the raw value")
    func preservesRawValue() {
        let identifier = Identifier<UserTag>(rawValue: "user-1")

        #expect(identifier.rawValue == "user-1")
    }

    @Test("round trips through Codable")
    func codableRoundTrip() throws {
        let identifier = Identifier<UserTag>(rawValue: "user-1")

        let data = try JSONEncoder().encode(identifier)
        let decoded = try JSONDecoder().decode(Identifier<UserTag>.self, from: data)

        #expect(decoded == identifier)
    }

    @Test("hashes equal values equally")
    func hashEquality() {
        let first = Identifier<UserTag>(rawValue: "user-1")
        let second = Identifier<UserTag>(rawValue: "user-1")

        #expect(Set([first, second]).count == 1)
    }
}
