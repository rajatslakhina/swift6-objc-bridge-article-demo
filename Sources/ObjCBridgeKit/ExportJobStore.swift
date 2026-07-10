/// The modern half of the codebase: an actor holding state under Swift 6
/// strict concurrency. `ExportJobStore` never talks to Objective-C
/// directly — it doesn't need to know the runtime exists.
public actor ExportJobStore {
    public private(set) var completedPaths: [String] = []
    public private(set) var failureMessages: [String] = []

    public init() {}

    public func recordSuccess(path: String) {
        completedPaths.append(path)
    }

    public func recordFailure(_ message: String) {
        failureMessages.append(message)
    }
}
