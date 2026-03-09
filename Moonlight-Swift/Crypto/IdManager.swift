//
//  IdManager.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 10.03.2026.
//

import Foundation

class IdManager {
    static var uniqueId: String {
        // TODO: Implement stable UUID
        return generateUniqueId()
    }

    private static func generateUniqueId() -> String {
        let uuidLong = UInt64(arc4random()) << 32 | UInt64(arc4random())
        return String(format: "%016llx", uuidLong)
    }
}
