//
//  SwiftUIToUIKit.swift
//  PJCore
//
//  Created by Даниил Виноградов on 05.11.2025.
//

import SwiftUI
import UIKit

public extension View {
    var asController: UIViewController {
        HostingController(rootView: self)
    }

    func asController(zoomPresentation source: UIView? = nil) -> UIViewController {
        HostingController(rootView: self, zoomPresentation: source)
    }

    func asController(zoomPresentation source: UIBarButtonItem? = nil) -> UIViewController {
        HostingController(rootView: self, zoomPresentation: source)
    }

    var asView: UIView {
        HostingView(content: { self })
    }
}
