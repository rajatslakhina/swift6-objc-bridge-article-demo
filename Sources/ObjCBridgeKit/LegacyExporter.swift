import Foundation

/// Mirrors a legacy Objective-C delegate protocol — the kind you'd find
/// declared in an old `.h` file inside a video/PDF export engine nobody
/// on the team wants to touch. Frameworks like this still run in plenty
/// of production iOS apps sitting right next to a modern Swift 6 stack.
///
/// The Objective-C runtime dispatches these methods synchronously, from
/// whatever thread the underlying work happens to finish on. It has no
/// concept of `async`, actors, or `Sendable` — those are pure Swift
/// compiler constructs that stop existing the moment a call crosses into
/// Objective-C.
public protocol LegacyExporterDelegate: NSObjectProtocol {
    func exporter(_ exporter: LegacyExporter, didFinishWithPath path: String)
    func exporter(_ exporter: LegacyExporter, didFailWithError error: NSError)
}

/// A stand-in for a legacy Objective-C export engine. It does real
/// background work on its own concurrent queue and calls its delegate
/// back from *that* queue — never hopping to the main thread, never
/// asking permission, exactly like the real thing.
///
/// `@unchecked Sendable` here is a deliberate, narrow claim, not a
/// shortcut: this type predates Swift 6 strict concurrency by design
/// (it is standing in for legacy code nobody is rewriting this
/// quarter) and it holds no actor-isolated state of its own — every
/// piece of state this article actually cares about protecting lives
/// downstream in `ExportJobStore`. Its only stored mutable field is a
/// `weak` delegate reference, and weak-reference reads/writes are
/// already made safe by ARC's side-table locking — a guarantee that
/// predates Swift concurrency entirely and that `Sendable` checking
/// isn't adding anything on top of here. That is a narrower claim
/// than "this class is safe" — it's "the one thing Swift can't see
/// through was already safe for an unrelated reason."
public final class LegacyExporter: NSObject, @unchecked Sendable {
    public weak var delegate: LegacyExporterDelegate?

    private let queue = DispatchQueue(
        label: "com.example.legacyexporter.queue",
        attributes: .concurrent
    )

    public override init() {
        super.init()
    }

    /// Starts a fire-and-forget export job on a random background thread.
    /// - Parameters:
    ///   - name: an identifier used to build the fake output path.
    ///   - simulatedFailure: forces the failure delegate callback instead
    ///     of success, so tests and the demo can exercise both paths.
    public func startExport(named name: String, simulatedFailure: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            // Simulate real export work taking a few milliseconds.
            Thread.sleep(forTimeInterval: 0.005)
            if simulatedFailure {
                let error = NSError(
                    domain: "LegacyExporter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Simulated export failure for \(name)"]
                )
                self.delegate?.exporter(self, didFailWithError: error)
            } else {
                self.delegate?.exporter(self, didFinishWithPath: "/tmp/\(name).export")
            }
        }
    }
}
