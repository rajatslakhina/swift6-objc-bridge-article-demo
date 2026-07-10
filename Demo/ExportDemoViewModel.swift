import Foundation
import Observation
import ObjCBridgeKit

/// Drives the demo screen. This is the "feed the UI directly" half of the
/// pattern: the same `ExportEventGateway` that a backend actor can drain
/// (see `ExportCoordinator` in the library) can just as easily be drained
/// by a `@MainActor`-isolated view model, which is what most SwiftUI
/// screens actually need.
@MainActor
@Observable
public final class ExportDemoViewModel {
    public private(set) var completedPaths: [String] = []
    public private(set) var failureMessages: [String] = []
    public private(set) var isRunning = false

    private let exporter = LegacyExporter()
    private let gateway = ExportEventGateway()
    private var pendingCount = 0
    private var observationTask: Task<Void, Never>?

    public init() {
        exporter.delegate = gateway
        observeEvents()
    }

    deinit {
        // Without this, the Task below would keep this view model alive
        // for as long as the app runs, even after the view disappears:
        // `gateway.events` never finishes on its own, so the `for await`
        // loop never returns by itself. Cancelling here is what lets the
        // suspended loop actually unwind — a plain `weak self` capture on
        // the Task does not, by itself, stop a loop body from re-binding
        // a strong `self` on every iteration it completes.
        observationTask?.cancel()
    }

    private func observeEvents() {
        observationTask = Task { [weak self] in
            guard let events = self?.gateway.events else { return }
            for await event in events {
                // Re-checking `weak self` on every iteration (instead of
                // once, up front) means this loop holds no strong
                // reference to `self` while it's suspended waiting for
                // the next event — only while actively handling one.
                guard let self else { break }
                switch event {
                case .finished(let path):
                    self.completedPaths.append(path)
                case .failed(let message):
                    self.failureMessages.append(message)
                }
                self.pendingCount -= 1
                if self.pendingCount <= 0 {
                    self.isRunning = false
                }
            }
        }
    }

    public func runBatch(count: Int = 8) {
        guard !isRunning else { return }
        completedPaths.removeAll()
        failureMessages.removeAll()
        pendingCount = count
        isRunning = true
        for i in 0..<count {
            exporter.startExport(named: "job-\(i)", simulatedFailure: i % 5 == 0)
        }
    }
}
