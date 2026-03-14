//
//  DiscoveryManager.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import Foundation
import SwiftData

@Observable
class DiscoveryManager {
    var hosts: [TemporaryHost] = []

    init(modelContainer: ModelContainer, isEnabled: Bool = true) {
        container = modelContainer
        self.isEnabled = isEnabled

        let loadedHosts = loadHosts()
        for host in loadedHosts {
            host.state = .unknown
            addHostToDiscovery(host)
        }
        hosts = hostQueue

        mdnsMan.callback = { [weak self] host in
            Task { await self?.updateHost(host) }
        }

        guard isEnabled else { return }

        CryptoManager.generateKeyPairUsingSSL()
        cert = CryptoManager.readCertFromFile()
    }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private var hostQueue: [TemporaryHost] = []
    private var pauseHosts: Set<TemporaryHost> = .init()
    private let mdnsMan: MDNSManager = .init()
    private var opQueue: OperationQueue = .init()
    private let uniqueId: String = IdManager.uniqueId
    private var cert: Data = .init()
    private var shouldDiscover: Bool = false
    private let isEnabled: Bool
}

extension DiscoveryManager {
    func startDiscovery() {
        guard isEnabled else { return }
        guard !shouldDiscover else { return }

        Log.i("Start discovery")
        shouldDiscover = true
        mdnsMan.searchForHosts()

        for host in hostQueue {
            if !pauseHosts.contains(host) {
                opQueue.addOperation(createWorkerForHost(host))
            }
        }
    }

    func stopDiscovery() {
        guard isEnabled else { return }
        guard shouldDiscover else { return }

        Log.i("Stopping discovery")
        shouldDiscover = false
        mdnsMan.stopSearching()
        opQueue.cancelAllOperations()
    }

    func stopDiscovery() async {
        guard isEnabled else { return }
        Log.i("Stopping discovery and waiting for workers to stop")

        if shouldDiscover {
            shouldDiscover = false
            mdnsMan.stopSearching()
            opQueue.cancelAllOperations()
        }

        await opQueue.drained()
        Log.i("All discovery workers stopped")
    }

    @discardableResult
    func addHostToDiscovery(_ host: TemporaryHost) -> Bool {
        guard !host.uuid.isEmpty else {
            return false
        }

        let existingHost = getHostInDiscovery(host.uuid)
        if let existingHost {
            // NB: Our logic here depends on the fact that we never propagate
            // the entire TemporaryHost to existingHost. In particular, when mDNS
            // discovers a PC and we poll it, we will do so over HTTP which will
            // not have accurate pair state. The fields explicitly copied below
            // are accurate though.

            // Update address of existing host
            if host.address != nil {
                existingHost.address = host.address
            }
            if host.localAddress != nil {
                existingHost.localAddress = host.localAddress
            }
            if host.ipv6Address != nil {
                existingHost.ipv6Address = host.ipv6Address
            }
            if host.externalAddress != nil {
                existingHost.externalAddress = host.externalAddress
            }
            existingHost.activeAddress = host.activeAddress
            existingHost.state = host.state
            return false
        } else {
            hostQueue.append(host)
            if shouldDiscover {
                opQueue.addOperation(createWorkerForHost(host))
            }
            return true
        }
    }

    func pauseDiscoveryForHost(_ host: TemporaryHost) {
//        opQueue.addBarrierBlock {
            for worker in opQueue.operations {
                guard let worker = worker as? DiscoveryWorker
                else { continue }

                if worker.host == host {
                    worker.cancel()
                }
            }
//        }

        pauseHosts.insert(host)
    }

    func resumeDiscoveryForHost(_ host: TemporaryHost) {
        // Remove it from the paused hosts list
        pauseHosts.remove(host)

        // Start discovery again
        if shouldDiscover {
            opQueue.addOperation(createWorkerForHost(host))
        }
    }
}

private extension DiscoveryManager {
    func createWorkerForHost(_ host: TemporaryHost) -> DiscoveryWorker {
        DiscoveryWorker(host: host, uniqueID: uniqueId)
    }

    func updateHost(_ host: TemporaryHost) async {
        // Discover the hosts before adding to eliminate duplicates
        Log.d("Found host through MDNS: \(host.name)")
        // Since this is on a background thread, we do not need to use the opQueue
        let worker = createWorkerForHost(host)
        await worker.discoverHost()
        if addHostToDiscovery(host) {
            Log.i("Found new host through MDNS: \(host.name)")
            context.insert(host)
            hosts = hostQueue
        } else {
            Log.d("Found existing host through MDNS: \(host.name)")
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    func getHostInDiscovery(_ uuid: String) -> TemporaryHost? {
        hostQueue.first(where: { $0.uuid == uuid })
    }

    func loadHosts() -> [TemporaryHost] {
        let descriptor = FetchDescriptor<TemporaryHost>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load hosts: \(error)")
            return []
        }
    }
}

extension OperationQueue {
    /// Suspends the current task until all operations currently in the queue have finished.
    /// Do not call this from within an operation running on the same queue, or you will deadlock.
    func drained() async {
        await withCheckedContinuation { continuation in
            self.addBarrierBlock {
                continuation.resume()
            }
        }
    }
}
