import XCTest
@testable import ObjCBridgeKit

final class ExportJobStoreTests: XCTestCase {

    func test_freshStoreStartsEmpty() async {
        let store = ExportJobStore()
        let paths = await store.completedPaths
        let failures = await store.failureMessages
        XCTAssertTrue(paths.isEmpty)
        XCTAssertTrue(failures.isEmpty)
    }

    func test_recordSuccessAppendsPath() async {
        let store = ExportJobStore()
        await store.recordSuccess(path: "/tmp/a.export")
        await store.recordSuccess(path: "/tmp/b.export")
        let paths = await store.completedPaths
        XCTAssertEqual(paths, ["/tmp/a.export", "/tmp/b.export"])
    }

    func test_recordFailureAppendsMessage() async {
        let store = ExportJobStore()
        await store.recordFailure("boom")
        let failures = await store.failureMessages
        XCTAssertEqual(failures, ["boom"])
    }
}
