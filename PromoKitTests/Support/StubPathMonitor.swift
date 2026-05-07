@testable import PromoKit

/// A `PromoPathMonitoring` stub that lets tests script connectivity transitions without
/// depending on real network state or constructing an `NWPath` (which has no public init).
final class StubPathMonitor: PromoPathMonitoring {
    var hasInternetAccess: Bool
    weak var delegate: PromoPathMonitorDelegate?

    init(connected: Bool) {
        self.hasInternetAccess = connected
    }

    func start() {}
    func cancel() {}

    func simulateConnectivityChange(_ connected: Bool) {
        hasInternetAccess = connected
        delegate?.pathMonitor(self, didUpdateConnectivity: connected)
    }
}
