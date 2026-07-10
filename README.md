# ObjCBridgeKit

A small, real Swift 6 library that demonstrates exactly where Swift's strict-concurrency guarantees (actor isolation, `Sendable`) stop applying once a call crosses into Objective-C — and one clean, tested pattern for bridging that gap safely instead of reaching for `@unchecked Sendable` everywhere.

This is the demo repo for the Medium article, ["Your Swift 6 Actors Are Safe. Your Objective-C Bridge Isn't Even Checked."](https://medium.com/@er.rajatlakhina/your-swift-6-actors-are-safe-your-objective-c-bridge-isnt-even-checked-449d21ab26cb), on migrating dual legacy-ObjC / modern-Swift-6 codebases.

## The problem, in one compiler error

The Objective-C runtime has no idea what an actor is. It dispatches delegate callbacks synchronously, from whatever thread the underlying work finishes on, and it will happily call into a Swift type that the compiler thinks is perfectly safe. Try to hand a `weak var` reference to a non-`Sendable` legacy type into a background-queue closure under Swift 6 strict concurrency, and you get exactly this, verbatim, from the compiler building this repo's own library:

```
error: capture of 'self' with non-sendable type 'LegacyExporter?' in a `@Sendable` closure
    queue.async { [weak self] in
        guard let self else { return }
```

Sendable checking is a compile-time-only, Swift-call-graph-only guarantee. The moment work crosses into a `DispatchQueue` shared with legacy code, or into a real Objective-C delegate callback, that guarantee has nothing left to check.

## The architecture

Three tiers, deliberately kept separate:

1. **`LegacyExporter`** — a stand-in for a legacy Objective-C export engine. Fires its delegate back from an arbitrary background thread, no awareness of Swift concurrency. Marked `@unchecked Sendable` with a narrow, written-out justification (see the doc comment in `Sources/ObjCBridgeKit/LegacyExporter.swift`): it holds no isolated state of its own, and its only mutable field is a `weak` reference already made safe by ARC.
2. **`ExportEventGateway`** — the *only* type that touches the legacy delegate protocol. It is deliberately dumb: no mutable state beyond an `AsyncStream` continuation, which Apple documents as safe to call concurrently from any thread. This is the one, carefully-justified crossing point.
3. **`ExportJobStore` + `ExportCoordinator`** — fully modern, actor-isolated Swift 6 code that drains the gateway's stream in strict arrival order and never has to think about Objective-C again.

```swift
public final class ExportEventGateway: NSObject, LegacyExporterDelegate, @unchecked Sendable {
    public enum Event: Sendable {
        case finished(path: String)
        case failed(message: String)
    }

    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    public func exporter(_ exporter: LegacyExporter, didFinishWithPath path: String) {
        continuation.yield(.finished(path: path))
    }
    // ...
}
```

```swift
public actor ExportCoordinator {
    public let store = ExportJobStore()

    public func start(consuming gateway: ExportEventGateway) {
        drainTask = Task { [store] in
            for await event in gateway.events {
                switch event {
                case .finished(let path): await store.recordSuccess(path: path)
                case .failed(let message): await store.recordFailure(message)
                }
            }
        }
    }
}
```

## What's tested (and why)

`swift test` — **9/9 passing**, no `@unchecked` anywhere in the test target itself:

- Sequential delegate calls preserve arrival order end-to-end.
- 200 concurrent callers firing at once lose zero events and produce zero duplicates (`Set` equality check).
- An empty stream (finished with zero events) drains immediately instead of hanging.
- Failure messages propagate through `NSError.localizedDescription` correctly.
- Two integration tests exercise the *real* `LegacyExporter` background-queue path end to end (success and failure), not just hand-fed delegate calls.

Run it yourself:

```bash
swift build
swift test
```

## The demo app

`Demo.xcodeproj` is a separate, hand-authored Xcode project in this same repo, consuming the library via a local Swift package reference (`XCLocalSwiftPackageReference relativePath="../"`) — no second repo to fetch. It fires a batch of 8 concurrent "legacy" export calls (one in five forced to fail) through the exact same gateway/coordinator pair the tests exercise, and shows live success/failure counts in a SwiftUI list.

**How to run it:** clone this repo, open `Demo/Demo.xcodeproj` in Xcode, pick any iPhone Simulator as the run destination, and hit Build & Run. No other setup, no signing changes needed for Simulator.

**Honest disclosure on verification tier for this run:** this repo was built and verified in an unattended, headless scheduled-task run with no access to macOS/Xcode/Simulator (Linux sandbox only). `swift build` and `swift test` above are real, both passing on a genuine Swift 6.0.3 toolchain. The `Demo.xcodeproj` project file was hand-authored, then checked with a script for balanced braces/parens and cross-referenced object IDs (all resolve, none dangling), and every `.swift` file under `Demo/` was checked with `swiftc -parse` for syntax validity. A live Simulator run was attempted — `request_access` for Xcode/Simulator was explicitly called — and the platform returned "Computer-use access ... can't be approved during a scheduled run," a hard restriction on unattended runs, not a judgment call to skip it. No screenshots exist in this repo as a result; `Demo/Screenshots/` is intentionally absent. In place of a live run, the SwiftUI files got a full manual crash-class review: the one retain-cycle risk found (a `Task` observing an `AsyncStream` that never finishes would have kept the view model alive indefinitely) was caught, fixed with a per-iteration `weak self` re-check plus a `deinit`-triggered cancellation, and the fix was verified empirically against a standalone reproduction of the exact pattern before being applied here — not just reasoned about.

**A genuinely interesting side-finding from building this headlessly:** the Linux Swift toolchain used to verify this library refuses to compile `@objc protocol ... : NSObjectProtocol` at all — `error: Objective-C interoperability is disabled`. Linux has no Objective-C runtime, full stop, which is itself a small, concrete illustration of this article's actual point: the ObjC bridge is a Darwin-only, runtime-level thing that Swift's own type system and tooling can't see through, or even build against, once it's gone. The delegate protocol in this repo is written as a plain Swift protocol with identical method signatures — on a real Xcode/Apple SDK, you'd mark it `@objc` for a genuine bridging header.

## License

MIT — copy whatever's useful.
