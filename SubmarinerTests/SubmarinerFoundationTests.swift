import XCTest
@testable import Submariner

final class SubmarinerFoundationTests: XCTestCase {
    func testFormEncodingEscapesParameterDelimiters() {
        let encoded = SubsonicFormEncoder.encode([
            URLQueryItem(name: "name", value: "A&B+C=D"),
            URLQueryItem(name: "space", value: "two words")
        ])

        XCTAssertEqual(encoded, "name=A%26B%2BC%3DD&space=two%20words")
    }

    func testMediaCacheIdentityIsServerScopedAndStable() {
        let first = MediaCache.cacheKey(
            serverURL: "https://one.example/music",
            username: "listener",
            trackID: "42",
            profile: "320"
        )
        let repeated = MediaCache.cacheKey(
            serverURL: "https://one.example/music",
            username: "listener",
            trackID: "42",
            profile: "320"
        )
        let otherServer = MediaCache.cacheKey(
            serverURL: "https://two.example/music",
            username: "listener",
            trackID: "42",
            profile: "320"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherServer)
        XCTAssertEqual(first.count, 64)
    }
}
