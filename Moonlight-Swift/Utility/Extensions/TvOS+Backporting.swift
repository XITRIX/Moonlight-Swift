//
//  TvOS+Backporting.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

#if os(tvOS)

import UIKit
import SwiftUI

extension UIColor {
//    static var secondarySystemBackground: UIColor {
//        
//    }
}

extension View {
    nonisolated public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
}

#endif
