//
//  ServerInfoResponse.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 10/03/2026.
//

import Foundation

private let TAG_HOSTNAME = "hostname"
private let TAG_EXTERNAL_IP = "ExternalIP"
private let TAG_HTTPS_PORT = "HttpsPort"
private let TAG_LOCAL_IP = "LocalIP"
let TAG_UNIQUE_ID = "uniqueid"
private let TAG_MAC_ADDRESS = "mac"
private let TAG_PAIR_STATUS = "PairStatus"
private let TAG_STATE = "state"
private let TAG_CURRENT_GAME = "currentgame"

// Sunshine extension
private let TAG_EXTERNAL_PORT = "ExternalPort"

class ServerInfoResponse: HttpResponse { }

extension ServerInfoResponse {
    func populateHost(_ host: TemporaryHost) {
        host.name = (getStringTag(TAG_HOSTNAME) ?? "").trim()
        host.uuid = (getStringTag(TAG_UNIQUE_ID) ?? "").trim()
        host.mac = (getStringTag(TAG_MAC_ADDRESS) ?? "").trim()
        host.currentGame = (getStringTag(TAG_CURRENT_GAME) ?? "").trim()

        if let httpsPort = getIntTag(TAG_HTTPS_PORT) {
            host.httpsPort = UInt16(httpsPort)
        } else {
            // Use the default if it's not specified
            host.httpsPort = 47984
        }

        // We might get an IPv4 loopback address if we're using GS IPv6 Forwarder
        let lanAddr = (getStringTag(TAG_LOCAL_IP) ?? "").trim()
        if !lanAddr.hasPrefix("127.") && !lanAddr.isEmpty {
            let localPort: UInt16

            // If we reached this host through this port, store our port there
            if let activeAddress = host.activeAddress,
               lanAddr == Utils.addressPortStringToAddress(activeAddress) {
                localPort = Utils.addressPortStringToPort(activeAddress)
            } else if let localAddress = host.localAddress {
                // If there's an existing local address, use the port from that
                localPort = Utils.addressPortStringToPort(localAddress)
            } else {
                // If all else fails, use 47989
                localPort = 47989
            }

            host.localAddress = Utils.addressAndPortToAddressPortString(lanAddr, port: localPort)
        }

        // This is a Sunshine extension for WAN port remapping
        let externalHttpPort: UInt16
        if let parsedPort = getIntTag(TAG_EXTERNAL_PORT) {
            externalHttpPort = UInt16(parsedPort)
        } else if let activeAddress = host.activeAddress {
            // Use our active port if it's not specified
            externalHttpPort = Utils.addressPortStringToPort(activeAddress)
        } else {
            // Otherwise use the default
            externalHttpPort = 47989
        }

        // Modern GFE versions don't actually give us a WAN address anymore
        // so we leave the one that we populated from mDNS discovery via STUN.
        let wanAddr = getStringTag(TAG_EXTERNAL_IP)?.trim()
        if let wanAddr, !wanAddr.isEmpty {
            host.externalAddress = Utils.addressAndPortToAddressPortString(wanAddr, port: externalHttpPort)
        } else if let existingExternal = host.externalAddress {
            // If we have an external address (via STUN) already, we still need to populate the port
            host.externalAddress = Utils.addressAndPortToAddressPortString(
                Utils.addressPortStringToAddress(existingExternal),
                port: externalHttpPort
            )
        }

        let state = (getStringTag(TAG_STATE) ?? "").trim()
        if !state.hasSuffix("_SERVER_BUSY") {
            // GFE 2.8 started keeping currentgame set to the last game played. As a result, it no longer
            // has the semantics that its name would indicate. To contain the effects of this change as much
            // as possible, we'll force the current game to zero if the server isn't in a streaming session.
            host.currentGame = "0"
        }

        // GFE uses the Mjolnir codename in their state enum values
        host.isNvidiaServerSoftware = state.contains("MJOLNIR")

        if let pairStatus = getIntTag(TAG_PAIR_STATUS) {
            host.pairState = pairStatus != 0 ? .paired : .unpaired
        } else {
            host.pairState = .unknown
        }

        if let serverCodecModeString = getStringTag("ServerCodecModeSupport") {
            host.serverCodecModeSupport = Int32(serverCodecModeString.trim()) ?? 0
        }
    }
}
