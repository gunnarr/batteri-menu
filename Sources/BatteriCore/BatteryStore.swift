import Foundation

/// The state behind the menu: what to show and whether it is being refreshed.
@MainActor
public final class BatteryStore: ObservableObject {
    public enum Phase: Equatable, Sendable {
        /// Nothing fetched yet.
        case loading
        case needsLogin
        case engineMissing
        case ready
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var devices: [Device] = []
    @Published public private(set) var updatedAt: Date?
    @Published public private(set) var isRefreshing = false
    /// Why the latest refresh failed. The previous devices stay visible.
    @Published public private(set) var lastError: String?

    private let fetch: @Sendable (_ includeFamily: Bool) async throws -> [Device]
    private let now: () -> Date

    public init(
        fetch: @escaping @Sendable (_ includeFamily: Bool) async throws -> [Device],
        now: @escaping () -> Date = Date.init
    ) {
        self.fetch = fetch
        self.now = now
    }

    public func refresh(includeFamily: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            devices = try await fetch(includeFamily)
            updatedAt = now()
            lastError = nil
            phase = .ready
        } catch EngineError.needsLogin {
            devices = []
            updatedAt = nil
            lastError = nil
            phase = .needsLogin
        } catch EngineError.notFound {
            phase = .engineMissing
        } catch EngineError.failed(let message) {
            lastError = message
            if phase == .loading || phase == .needsLogin { phase = .ready }
        } catch {
            lastError = error.localizedDescription
            if phase == .loading || phase == .needsLogin { phase = .ready }
        }
    }

    /// Forget everything after signing out.
    public func reset() {
        devices = []
        updatedAt = nil
        lastError = nil
        phase = .needsLogin
    }

    /// True when the data is older than `interval` (or missing).
    public func isStale(after interval: TimeInterval) -> Bool {
        guard let updatedAt else { return true }
        return now().timeIntervalSince(updatedAt) >= interval
    }
}
