import XCTest
@testable import NotchShareKit

final class MessageTests: XCTestCase {
    func testRoundTrip() throws {
        let m = NotchShareMessage(.tokenExchange, payload: Data([1, 2, 3]))
        XCTAssertEqual(try NotchShareMessage.decode(m.encoded()), m)
    }
    func testAllKindsEncode() throws {
        for k in [NotchShareMessage.Kind.ready, .cancel, .ack, .near, .far] {
            XCTAssertEqual(try NotchShareMessage.decode(NotchShareMessage(k).encoded()).kind, k)
        }
    }
}
