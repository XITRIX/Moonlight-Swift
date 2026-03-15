import UIKit
import SwiftUI

@available(visionOS, unavailable, message: "AirPlay external display is not supported on Vision Pro.")
public extension View {
    func airPlay() -> some View {
        // print("AirKit - airPlay")
        Air.play(AnyView(self))
        return self
    }
    
}

