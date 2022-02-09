import XCTest
final class TSElementaryStreamTests: XCTestCase {
    
    func testElementaryStreamCCounterCannotExceedMaxValue() {
        let stream = TSElementaryStream(pid: 256, streamType: TSStreamType.ADTSAAC)
        stream.continuityCounter = UInt8.max
        let uint4Max: UInt8 = 16
        XCTAssertEqual(stream.continuityCounter, UInt8.max % uint4Max)
    }

    static var allTests = [
        ("testElementaryStreamCCounterCannotExceedMaxValue", testElementaryStreamCCounterCannotExceedMaxValue),
    ]
}
