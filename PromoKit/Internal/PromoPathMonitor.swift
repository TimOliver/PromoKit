//
//  PromoPathMonitor.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import Network
import os.lock

/// Tracks network path status and reports changes on the main queue.
internal class PromoPathMonitor: PromoPathMonitoring {

    // Whether the monitor is running or not
    private(set) public var isRunning = false

    // The last captured path value from the path monitor
    private(set) public var currentPath: NWPath?

    // Stored separately to allow status transitions without constructing an NWPath.
    private var currentStatus: NWPath.Status?

    // Delegate that broadcasts when the status changes
    public weak var delegate: PromoPathMonitorDelegate?

    // A shared dispatch queue for receiving network update events
    static let networkPathQueue = DispatchQueue(label: "dev.tim.promokit.network", qos: .utility)

    // Tracking when we come online and offline
    let pathMonitor = NWPathMonitor()

    // Protects the path and status while updates arrive on the network queue.
    let unfairLock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()

    deinit {
        pathMonitor.cancel()
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    /// Begins monitoring network path changes. Has no effect if already running.
    public func start() {
        guard !isRunning else { return }

        // Start listening for network updates
        pathMonitor.start(queue: PromoPathMonitor.networkPathQueue)
        pathMonitor.pathUpdateHandler = { [weak self] newPath in
            self?.pathDidUpdate(to: newPath)
        }

        isRunning = true
    }

    /// Stops monitoring network path changes. Has no effect if not running.
    public func cancel() {
        guard isRunning else { return }
        pathMonitor.cancel()
        isRunning = false
    }

    /// Whether the current network path is satisfied. May be read from any queue.
    /// Defaults to `true` until the first status arrives so initial fetches can proceed.
    /// A satisfied path does not guarantee that a provider's request will succeed.
    public var hasInternetAccess: Bool {
        // Read the status under the same lock used by network updates.
        var value = true
        os_unfair_lock_lock(unfairLock)
        if let currentStatus {
            value = currentStatus == .satisfied
        }
        os_unfair_lock_unlock(unfairLock)
        return value
    }
}

extension PromoPathMonitor {

    /// Records a path update. The first establishes the initial status;
    /// subsequent status changes notify the delegate on the main queue.
    func pathDidUpdate(to path: NWPath) {
        pathDidUpdate(to: path.status, currentPath: path)
    }

    func pathDidUpdate(to status: NWPath.Status, currentPath path: NWPath? = nil) {
        // Only changes after the initial status produce a delegate callback.
        var statusDidChange = false
        os_unfair_lock_lock(unfairLock)
        if let currentStatus {
            statusDidChange = currentStatus != status
        }
        currentStatus = status
        if let path {
            currentPath = path
        }
        os_unfair_lock_unlock(unfairLock)
        if !statusDidChange { return }

        // Deliver both connection and disconnection changes on the main queue.
        let connected = status == .satisfied
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.pathMonitor(self, didUpdateConnectivity: connected)
        }
    }
}
