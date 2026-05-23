import XCTest
@testable import CareLoop

final class KeychainStoreTests: XCTestCase {
    func test_setGetAndRemove_roundTripsValue() {
        let key = "test.token.\(UUID().uuidString)"

        KeychainStore.set("token-123", for: key)
        XCTAssertEqual(KeychainStore.get(key), "token-123")

        KeychainStore.remove(key)
        XCTAssertNil(KeychainStore.get(key))
    }
}
