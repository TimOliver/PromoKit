//
//  PromoPathMonitor.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 1/4/2024.
//

import Foundation
import Network
import os.lock

protocol PromoPathMonitorDelegate: AnyObject {
    /// The network monitor status changed
    /// - Parameters:
    ///   - pathMonitor: The path monitor tracking these changes
    ///   - didUpdateToPath: The path that was updated
    func pathMonitor(_ pathMonitor: PromoPathMonitor, didUpdateToPath path: NWPath?)
}

/// Used to track the current connectivity state of the device and provide
/// notifications when a valid internet connection appears or drops.
internal class PromoPathMonitor {

    // Whether the monitor is running or not
    private(set) public var isRunning = false

    // The last captured path value from the path monitor
    private(set) public var currentPath: NWPath?

    // Delegate that broadcasts when the status changes
    public weak var delegate: PromoPathMonitorDelegate?

    // A shared dispatch queue for receiving network update events
    static let networkPathQueue = DispatchQueue(label: "dev.tim.promokit.network", qos: .utility)

    // Tracking when we come online and offline
    let pathMonitor = NWPathMonitor()

    // Thread-safe lock for mutating the internet access flag
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

    public func start() {
        guard !isRunning else { return }

        // Start listening for network updates
        pathMonitor.start(queue: PromoPathMonitor.networkPathQueue)
        pathMonitor.pathUpdateHandler = { [weak self] newPath in
            self?.pathDidUpdate(to: newPath)
        }

        isRunning = true
    }

    public func cancel() {
        guard isRunning else { return }
        pathMonitor.cancel()
        isRunning = false
    }

    public var hasInternetAccess: Bool {
        // In case it's being mutated on another thread,
        // use a lock to fetch the current path status
        // and check if we're online.
        var value = false
        os_unfair_lock_lock(unfairLock)
        if let currentPath {
            value = currentPath.status == .satisfied
        }
        os_unfair_lock_unlock(unfairLock)
        return value
    }
}

extension PromoPathMonitor {

    private func pathDidUpdate(to path: NWPath) {
        // Since NWPathMonitor constantly sends updates,
        // we'll use our background thread to detect and discard
        // events that don't actually change the status.
        var statusDidChange = false
        os_unfair_lock_lock(unfairLock)
        if let currentPath {
            statusDidChange = currentPath.status != path.status
        }
        currentPath = path
        os_unfair_lock_unlock(unfairLock)
        if !statusDidChange { return }

        // If we were showing offline content, and the internet came back up,
        // perform a new fetch to see if there's an online provider we should show
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.pathMonitor(self, didUpdateToPath: path)
        }
    }
}
