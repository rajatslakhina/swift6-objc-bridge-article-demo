import Foundation

/// The crossing point between the Objective-C world and Swift 6's actor
/// isolation — and the whole point of this library.
///
/// `ExportEventGateway` is the *only* type that conforms to the `@objc`
/// delegate protocol. It is deliberately dumb: it holds no mutable state
/// of its own, so there is nothing for a data race to corrupt. Its single
/// job is to turn a synchronous, arbitrary-thread Objective-C callback
/// into a value pushed onto an ordered stream that a Swift actor can
/// drain safely, one event at a time.
///
/// Marking this type `@unchecked Sendable` is safe — not just convenient
/// — for two concrete, checkable reasons:
/// 1. `continuation` is a `let`: assigned once in `init` and never
///    mutated again, so there is no shared mutable state to protect.
/// 2. `AsyncStream<Event>.Continuation.yield(_:)` is documented by Apple
///    as safe to call concurrently from multiple threads. That guarantee
///    is exactly what makes this bridge safe despite the Objective-C
///    runtime calling in from wherever it wants.
public final class ExportEventGateway: NSObject, LegacyExporterDelegate, @unchecked Sendable {
    public enum Event: Sendable {
        case finished(path: String)
        case failed(message: String)
    }

    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    public override init() {
        // The implicitly-unwrapped optional here is safe, not a shortcut:
        // `AsyncStream.init(_:)` invokes its build closure synchronously,
        // before the initializer for `AsyncStream` itself returns, so
        // `capturedContinuation` is guaranteed to be assigned before the
        // next line reads it. This is the standard, Apple-documented way
        // to capture a stream's continuation for storage elsewhere.
        var capturedContinuation: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        super.init()
    }

    public func exporter(_ exporter: LegacyExporter, didFinishWithPath path: String) {
        continuation.yield(.finished(path: path))
    }

    public func exporter(_ exporter: LegacyExporter, didFailWithError error: NSError) {
        continuation.yield(.failed(message: error.localizedDescription))
    }

    /// Signals that no more delegate calls are expected, so consumers of
    /// `events` can finish draining and return.
    public func finish() {
        continuation.finish()
    }
}
