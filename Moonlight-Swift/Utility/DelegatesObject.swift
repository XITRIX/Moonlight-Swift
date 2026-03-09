//
//  DelegatesObject.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 10/03/2026.
//

import Foundation

class DelegatesObject<Parent: AnyObject>: NSObject {
    weak var parent: Parent!

    init(parent: Parent) {
        self.parent = parent
    }
}
