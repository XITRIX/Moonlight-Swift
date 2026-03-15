//
//  Array+InNilOrEmpty.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 15.03.2026.
//

import Foundation

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
