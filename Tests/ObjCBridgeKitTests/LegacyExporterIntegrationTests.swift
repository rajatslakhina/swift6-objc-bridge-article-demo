import XCTest
@testable import ObjCBridgeKit

/// End-to-end tests that go through the real `LegacyExporter` background
/// queue instead of calling the delegate methods directly — proving the
/// gateway/coordinator pairing works against the actual "legacy"
/// call path, not just a hand-fed one.
final class LegacyExporterIntegrationTests: XCTestCase {

    func test_legacyExporterInvokesDelegateOnSuccess() async {
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        let exporter = LegacyExporter()
        exporter.delegate = gateway
        exporter.startExport(named: "single-job")

        // A short, generous wait for the legacy background queue to call
        // back — the same kind of margin you'd need against a real
        // framework you don't control and can't instrument directly.
        try? await Task.sleep(nanoseconds: 200_000_000)
        gateway.finish()
        await coordinator.waitUntilDrained()

        let paths = await coordinator.store.completedPaths
        XCTAssertEqual(paths, ["/tmp/single-job.export"])
    }

    func test_legacyExporterInvokesDelegateOnFailure() async {
        let gateway = ExportEventGateway()
        let coordinator = ExportCoordinator()
        await coordinator.start(consuming: gateway)

        let exporter = LegacyExporter()
        exporter.delegate = gateway
        exporter.startExport(named: "will-fail", simulatedFailure: true)

        try? await Task.sleep(nanoseconds: 200_000_000)
        gateway.finish()
        await coordinator.waitUntilDrained()

        let failures = await coordinator.store.failureMessages
        // .first (not a bare subscript) so a wrong count fails cleanly
        // via the assertion below rather than crashing the test run.
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.contains("will-fail"), true)
    }
}
