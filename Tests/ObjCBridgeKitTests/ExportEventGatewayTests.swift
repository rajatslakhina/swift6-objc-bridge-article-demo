import XCTest
@testable import ObjCBridgeKit

final class ExportEventGatewayTests: XCTestCase {

    func test_sequentialEventsPreserveOrder() async {
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        let exporter = LegacyExporter()
        // Calling the delegate methods directly (instead of going through
        // startExport's real background queue) lets this test pin down
        // an exact, deterministic order to assert against.
        gateway.exporter(exporter, didFinishWithPath: "a")
        gateway.exporter(exporter, didFailWithError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "b"]))
        gateway.exporter(exporter, didFinishWithPath: "c")
        gateway.finish()

        await coordinator.waitUntilDrained()

        let paths = await coordinator.store.completedPaths
        let failures = await coordinator.store.failureMessages
        XCTAssertEqual(paths, ["a", "c"])
        XCTAssertEqual(failures, ["b"])
    }

    func test_emptyStreamDrainsImmediately() async {
        // Edge case: a gateway that never receives a single delegate call
        // before being finished should drain to an empty, non-hanging
        // result rather than deadlocking `waitUntilDrained()`.
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        gateway.finish()
        await coordinator.waitUntilDrained()

        let paths = await coordinator.store.completedPaths
        let failures = await coordinator.store.failureMessages
        XCTAssertTrue(paths.isEmpty)
        XCTAssertTrue(failures.isEmpty)
    }

    func test_failureMessagePropagatesLocalizedDescription() async {
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        let exporter = LegacyExporter()
        let error = NSError(domain: "LegacyExporter", code: 42, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        gateway.exporter(exporter, didFailWithError: error)
        gateway.finish()
        await coordinator.waitUntilDrained()

        let failures = await coordinator.store.failureMessages
        XCTAssertEqual(failures, ["disk full"])
    }

    func test_concurrentDeliveryFromManyCallersLosesNoEvents() async {
        // This is the scenario the whole library exists for: many
        // "legacy" callers each firing a delegate callback at the same
        // time, from concurrently-running code the gateway does not
        // control. Nothing should be lost, duplicated, or crash.
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        let total = 200
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<total {
                group.addTask {
                    // A fresh instance per task stands in for "many
                    // different arbitrary-thread callers" without
                    // sharing a non-Sendable object across the boundary.
                    let exporter = LegacyExporter()
                    gateway.exporter(exporter, didFinishWithPath: "job-\(i)")
                }
            }
        }
        gateway.finish()
        await coordinator.waitUntilDrained()

        let paths = await coordinator.store.completedPaths
        XCTAssertEqual(paths.count, total)
        XCTAssertEqual(Set(paths).count, total, "every job path should be unique and present — none lost, none duplicated")
    }
}
