/// Owns the actor-isolated `ExportJobStore` and drains an
/// `ExportEventGateway`'s stream in strict arrival order — the ordering
/// guarantee the raw `@objc` callback boundary cannot give you for free.
public actor ExportCoordinator {
    public let store = ExportJobStore()
    private var drainTask: Task<Void, Never>?

    public init() {}

    /// Begins consuming `gateway.events`. Safe to call once per gateway.
    public func start(consuming gateway: ExportEventGateway) {
        guard drainTask == nil else { return }
        drainTask = Task { [store] in
            for await event in gateway.events {
                switch event {
                case .finished(let path):
                    await store.recordSuccess(path: path)
                case .failed(let message):
                    await store.recordFailure(message)
                }
            }
        }
    }

    /// Suspends until the gateway has been `finish()`-ed and every event
    /// already yielded has been drained into the store.
    public func waitUntilDrained() async {
        await drainTask?.value
    }
}
