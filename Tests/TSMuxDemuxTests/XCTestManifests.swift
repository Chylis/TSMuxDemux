import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(TSElementaryStreamTests.allTests),
        testCase(TSPacketTests.allTests)
    ]
}
#endif
