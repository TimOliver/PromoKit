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

    func testPathMonitorHasInternetAccessDefaultsToTrueBeforeAnyPathArrives() {
        // Optimistic default: before NWPathMonitor has reported its first
        // path, hasInternetAccess returns true so a synchronous fetch issued
        // immediately after construction isn't blocked by the racy first
        // callback on real devices/simulators. Genuine offline state is
        // picked up by the next path update (covered separately below).
        let monitor = PromoPathMonitor()
        XCTAssertTrue(monitor.hasInternetAccess)
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

    func testPathMonitorNotifiesDelegateOnlyWhenConnectivityChanges() {
        let monitor = PromoPathMonitor()
        let delegate = PathMonitorDelegateSpy()
        monitor.delegate = delegate

        monitor.pathDidUpdate(to: .unsatisfied)
        XCTAssertFalse(monitor.hasInternetAccess)
        XCTAssertEqual(delegate.connectivityUpdates, [])

        let online = expectation(description: "Delegate receives online transition")
        delegate.onUpdate = {
            if $0 == true { online.fulfill() }
        }
        monitor.pathDidUpdate(to: .satisfied)
        wait(for: [online], timeout: 1.0)

        XCTAssertTrue(monitor.hasInternetAccess)
        XCTAssertEqual(delegate.connectivityUpdates, [true])

        monitor.pathDidUpdate(to: .satisfied)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(delegate.connectivityUpdates, [true])

        let offline = expectation(description: "Delegate receives offline transition")
        delegate.onUpdate = {
            if $0 == false { offline.fulfill() }
        }
        monitor.pathDidUpdate(to: .unsatisfied)
        wait(for: [offline], timeout: 1.0)

        XCTAssertFalse(monitor.hasInternetAccess)
        XCTAssertEqual(delegate.connectivityUpdates, [true, false])
    }
}

private final class PathMonitorDelegateSpy: PromoPathMonitorDelegate {
    var connectivityUpdates = [Bool]()
    var onUpdate: ((Bool) -> Void)?

    func pathMonitor(_ pathMonitor: PromoPathMonitoring, didUpdateConnectivity connected: Bool) {
        connectivityUpdates.append(connected)
        onUpdate?(connected)
    }
}
