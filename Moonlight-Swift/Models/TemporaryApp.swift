//
//  TemporaryApp.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

import Foundation

class TemporaryApp: Identifiable {
    var id: String
    var name: String
    var installPath: String?
    var hdrSupported: Bool
    var hidden: Bool
    var host: TemporaryHost

    init(id: String,
         name: String,
         installPath: String? = nil,
         hdrSupported: Bool = false,
         hidden: Bool = false,
         host: TemporaryHost)
    {
        self.id = id
        self.name = name
        self.installPath = installPath
        self.hdrSupported = hdrSupported
        self.hidden = hidden
        self.host = host
    }
}
