public protocol ContentLoading: Sendable {
    func loadInitialContent() async throws
}

public struct ContentLoader: ContentLoading {
    public init() {}

    public func loadInitialContent() async throws {}
}
