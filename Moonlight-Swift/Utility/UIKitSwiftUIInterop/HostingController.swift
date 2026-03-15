//
//  HostingController.swift
//  PJCore
//
//  Created by Даниил Виноградов on 05.11.2025.
//

import SwiftUI
import UIKit

private struct ControllerKey: EnvironmentKey {
    static let defaultValue: UIViewController? = nil
}

private struct MarginsKey: EnvironmentKey {
    static let defaultValue: NSDirectionalEdgeInsets = .init()
}

public extension EnvironmentValues {
    @MainActor
    var controller: UIViewController? {
        get { self[ControllerKey.self] }
        set { self[ControllerKey.self] = newValue }
    }

    @MainActor
    var systemMargins: NSDirectionalEdgeInsets {
        get { self[MarginsKey.self] }
        set { self[MarginsKey.self] = newValue }
    }
}

struct ControllerInjected<Inner: View>: View {
    private let controller: UIViewController
    private let margins: NSDirectionalEdgeInsets
    let inner: Inner

    init(controller: UIViewController, inner: Inner, margins: NSDirectionalEdgeInsets = .zero) {
        self.controller = controller
        self.inner = inner
        self.margins = margins
    }

    var body: some View {
        inner
            .environment(\.controller, controller)
            .environment(\.systemMargins, margins)
    }
}

class HostingController<Content: View>: UIHostingController<ControllerInjected<Content>> {
    init(rootView: Content) {
        let wrapped = ControllerInjected(controller: UIViewController(), inner: rootView)
        super.init(rootView: wrapped)

        self.rootView = ControllerInjected(controller: self, inner: rootView)
    }

    convenience init(rootView: Content, zoomPresentation source: UIView?) {
        self.init(rootView: rootView)

        if #available(iOS 18, *), let source {
            preferredTransition = .zoom(sourceViewProvider: { _ in
                source
            })
        }
    }

    convenience init(rootView: Content, zoomPresentation source: UIBarButtonItem?) {
        self.init(rootView: rootView)

        if #available(iOS 26, *), let source {
            preferredTransition = .zoom(sourceBarButtonItemProvider: { context in
                source
            })
        }
    }

    @available(*, unavailable)
    @MainActor @preconcurrency dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        self.rootView = ControllerInjected(controller: self, inner: rootView.inner, margins: view.directionalLayoutMargins)
    }
}
