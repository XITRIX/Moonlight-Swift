//
//  visionOS+Glass.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 15.03.2026.
//

import SwiftUI

#if os(visionOS)

public enum Glass {
    case regular
}

extension View {
    nonisolated public func glassEffect(_ glass: Glass = .regular, in shape: some Shape = .rect(cornerRadius: 25)) -> some View {
        self
    }
}


extension ToolbarContent {
    nonisolated public func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        self
    }
}
#endif
