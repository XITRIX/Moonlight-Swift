//
//  TemporaryHost.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 08.03.2026.
//

import Foundation
import SwiftData

@Model
class TemporaryHost: Hashable {
    @Attribute(.unique)
    var uuid: String
    var id: String { uuid }
    
    var state: State
    var pairState: PairState
    var activeAddress: String?
    var currentGame: String?
    var httpsPort: UInt16
    var isNvidiaServerSoftware: Bool

    var serverCert: Data?
    var address: String?
    var externalAddress: String?
    var localAddress: String?
    var ipv6Address: String?
    var mac: String?
    var serverCodecModeSupport: Int32

    var name: String

    init(state: State = .unknown,
         pairState: PairState = .unknown,
         activeAddress: String? = nil,
         currentGame: String? = nil,
         httpsPort: UInt16 = 0,
         isNvidiaServerSoftware: Bool = false,
         serverCert: Data? = nil,
         address: String? = nil,
         externalAddress: String? = nil,
         localAddress: String? = nil,
         ipv6Address: String? = nil,
         mac: String? = nil,
         serverCodecModeSupport: Int32 = 0,
         name: String = "",
         uuid: String = "")
    {
        self.state = state
        self.pairState = pairState
        self.activeAddress = activeAddress
        self.currentGame = currentGame
        self.httpsPort = httpsPort
        self.isNvidiaServerSoftware = isNvidiaServerSoftware
        self.serverCert = serverCert
        self.address = address
        self.externalAddress = externalAddress
        self.localAddress = localAddress
        self.ipv6Address = ipv6Address
        self.mac = mac
        self.serverCodecModeSupport = serverCodecModeSupport
        self.name = name
        self.uuid = uuid
    }
}

extension TemporaryHost {
    enum State: Int, Codable, Identifiable {
        var id: Self { self }
        case unknown
        case offline
        case online
    }

    enum PairState: Int, Codable, Identifiable {
        var id: Self { self }
        case unknown
        case unpaired
        case paired
    }
}
