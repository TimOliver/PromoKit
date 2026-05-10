import XCTest
import Network
@testable import PromoKit

@MainActor
final class PromoPathMonitorTests: XCTestCase {

    func testPathMonitorStartIsIdempotentAndCancelStops() {
        let monitor = PromoPathMonitor()
        XCTAssertFalse(monitor.isRunning)

        monitor.start()
        XCTAssertTrue(monitor.isRunning)

        // Calling start() while already running should be a no-op — verifies the guard
        // at the top of start() and prevents double-installing the path-update handler.
        monitor.start()
        XCTAssertTrue(monitor.isRunning)

        monitor.cancel()
        XCTAssertFalse(monitor.isRunning)

        // Cancel while stopped is a no-op too.
        monitor.cancel()
        XCTAssertFalse(monitor.isRunning)
    }

    func testPathMonitorHasInternetAccessIsFalseBeforeAnyPathArrives() {
        // Without start() the monitor has no captured path — hasInternetAccess must report
        // false rather than crashing when reading through the unfair lock.
        let monitor = PromoPathMonitor()
        XCTAssertFalse(monitor.hasInternetAccess)
    }

    func testPathMonitorReceivesAtLeastOnePathUpdateAfterStart() {
        // NWPathMonitor delivers an initial path event shortly after start() — exercising
        // the synchronous portion of pathDidUpdate(to:): lock acquisition, status comparison,
        // and currentPath assignment. We can't drive a connectivity transition from a test,
        // so the delegate-callback branch isn't reached here.
        let monitor = PromoPathMonitor()
        defer { monitor.cancel() }

        monitor.start()

        // Poll on the main queue using a runloop spin so we don't need to bounce between
        // queues to read currentPath. NWPathMonitor's update is delivered on its own queue
        // and writes through the unfair lock, so the value becomes visible to subsequent reads.
        let deadline = Date().addingTimeInterval(5.0)
        while monitor.currentPath == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertNotNil(monitor.currentPath,
                        "NWPathMonitor should deliver at least one event after start()")
    }
}
