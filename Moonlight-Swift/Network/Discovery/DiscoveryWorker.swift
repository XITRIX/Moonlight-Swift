//
//  DiscoveryWorker.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 10.03.2026.
//

import Foundation

class DiscoveryWorker: Operation, @unchecked Sendable {
    let host: TemporaryHost
    private let uniqueID: String

    private static let poolRate = 2.0

    init(host: TemporaryHost, uniqueID: String) {
        self.host = host
        self.uniqueID = uniqueID
    }

    override func main() {
        while !isCancelled {
            Task { await discoverHost() }
            if !isCancelled {
                Thread.sleep(forTimeInterval: Self.poolRate)
            }
        }
    }
}

extension DiscoveryWorker {
    func discoverHost() async {
        var receivedResponse: Bool = false
        let addresses: [String] = getHostAddressList()

        Log.d("\(host.name) has \(addresses.count) unique addresses")

        // Give the PC 2 tries to respond before declaring it offline if we've seen it before.
        // If this is an unknown PC, update the status after 1 attempt to get the UI refreshed quickly.
        let limit = host.state == .unknown ? 1 : 2
        for i in 0 ..< limit {
            for address in addresses {
                guard !isCancelled else { return }

                let serverInfoResp = await requestInfoAtAddress(address, cert: host.serverCert)
                receivedResponse = checkResponse(serverInfoResp)
                if receivedResponse {
                    host.activeAddress = address
                    serverInfoResp.populateHost(host)

                    // Update the database using the response
                    //TODO: Implement Database
                    break
                }
            }

            if receivedResponse {
                Log.d("Received serverinfo response on try \(i)")
                break
            }
        }

        host.state = receivedResponse ? .online : .offline
        if receivedResponse {
            Log.d("Received response from: \(host.name)\n{\n\t address:\(host.address) \n\t localAddress:\(host.localAddress) \n\t externalAddress:\(host.externalAddress) \n\t ipv6Address:\(host.ipv6Address) \n\t uuid:\(host.uuid) \n\t mac:\(host.mac) \n\t pairState:\(host.pairState) \n\t online:\(host.state) \n\t activeAddress:\(host.activeAddress) \n}");
        }
    }
}

private extension DiscoveryWorker {
    func getHostAddressList() -> [String] {
        var array: [String] = []

        if let address = host.localAddress {
            array.append(address)
        }
        if let address = host.address {
            array.append(address)
        }
        if let address = host.externalAddress {
            array.append(address)
        }
        if let address = host.ipv6Address {
            array.append(address)
        }

        // Remove duplicate addresses from the list.
        // This is done using an array rather than a set
        // to preserve insertion order of addresses.
        return array.uniqued()
    }

    func requestInfoAtAddress(_ address: String, cert: Data?) async -> ServerInfoResponse {
        let hMan = HttpManager(hostAddressPortString: address, httpsPort: nil, serverCert: cert)
        let response = ServerInfoResponse()
        await hMan.executeRequest(.init(for: response, with: hMan.newServerInfoRequest(fastFail: true), fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))
        return response
    }

    func checkResponse(_ response: ServerInfoResponse) -> Bool {
        guard response.isStatusOk else { return false }

        // If the response is from a different host then do not update this host
        if host.uuid.isEmpty || response.getStringTag(TAG_UNIQUE_ID) == host.uuid {
            return true
        }

        Log.i("Received response from incorrect host: \(response.getStringTag(TAG_UNIQUE_ID) ?? "UNKNOWN") expected: \(host.uuid)");
        return false
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
