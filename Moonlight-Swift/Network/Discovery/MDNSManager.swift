//
//  MDNSManager.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import Foundation

public class MDNSManager: NSObject {
    var callback: (TemporaryHost) -> Void = { _ in }

    override init() {
        super.init()
        dnsBrowser.delegate = self
    }

    private let dnsBrowser: NetServiceBrowser = .init()
    private var services: [NetService] = []
    private var scanActive: Bool = false
    private var timerPending: Bool = false

    static private let nvServiceType: String = "_nvstream._tcp"
}

public extension MDNSManager {
    func searchForHosts() {
        guard !scanActive else { return }

        Log.i("Starting mDNS discovery")
        scanActive = true

        if !timerPending {
            timerPending = true
            startSearchTimerCallback()
        }
    }

    func stopSearching() {
        guard scanActive else { return }

        Log.i("Stopping mDNS discovery")
        scanActive = false
        dnsBrowser.stop()
    }

    func forgetHosts() {
        services.removeAll()
    }
}

extension MDNSManager: NetServiceDelegate {
    public func netServiceDidResolveAddress(_ service: NetService) {
        let addresses = service.addresses ?? []

        for addrData in addresses {
            Log.i("Resolved address: \(service.hostName ?? "Unknown") -> \(addrData.ipv4()?.ipString() ?? "Unknown")")
        }

        let host: TemporaryHost = .init()

        // First, look for an IPv4 record for the local address
        for addrData in addresses {
            guard let sin = addrData.ipv4(),
                  sin.sin_family == AF_INET
            else { continue }

            if !Utils.isActiveNetworkVPN() {
                var wanAddr: in_addr = .init()
                let err = LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &wanAddr.s_addr)
                if err == 0 {
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let addrStr = buf.withUnsafeMutableBufferPointer { ptr -> String? in
                        guard inet_ntop(AF_INET, &wanAddr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN)) != nil else {
                            return nil
                        }
                        return String(cString: ptr.baseAddress!)
                    }
                    host.externalAddress = addrStr
                    Log.i("External IPv4 address (STUN): \(service.hostName ?? "Unknown") -> \(host.externalAddress ?? "Unknown")")
                } else {
                    Log.e("STUN failed to get WAN address: \(err)")
                }
            }

            host.localAddress = addrData.ipv4()?.ipString()
            Log.i("Local address chosen: \(service.hostName ?? "Unknown") -> \(host.localAddress ?? "Unknown")")
            break
        }

        // TODO: Implement IPv6

        host.activeAddress = host.localAddress
        host.name = service.hostName ?? "Unknown"
        callback(host)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        Log.w("Did not resolve address for: \(sender)\n\(errorDict.description)")

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.retryResolveTimerCallback(sender)
        }
    }
}

extension MDNSManager: NetServiceBrowserDelegate {
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Log.d("Found service: \(service)")

        if !services.contains(service) {
            Log.i("Found new host: \(service.name)")
            service.delegate = self
            service.resolve(withTimeout: 5.0)
            services.append(service)
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Log.i("Removing service: \(service)")
        services.removeAll(where: { $0 == service })
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        Log.w("Did not perform search: \n\(errorDict.description)")
        // We'll schedule a retry in startSearchTimerCallback
    }
}

private extension MDNSManager {
    func startSearchTimerCallback() {
        guard scanActive else {
            timerPending = false
            return
        }

        Log.d("Restarting mDNS search")
        dnsBrowser.stop()
        dnsBrowser.searchForServices(ofType: Self.nvServiceType, inDomain: "")

        // Search again in 5 seconds. We need to do this because
        // we want more aggressive querying than Bonjour will normally
        // do for when we're at the hosts screen. This also covers scenarios
        // where discovery didn't work, like if WiFi was disabled.
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.startSearchTimerCallback()
        }
    }

    func retryResolveTimerCallback(_ service: NetService) {
        // Check if we've been stopped since this was queued
        guard scanActive else { return }

        Log.i("Retrying mDNS resolution for \(service)")

        if service.hostName == nil {
            service.delegate = self
            service.resolve(withTimeout: 5)
        }
    }
}
