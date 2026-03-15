//
//  UIKitToSwiftUI.swift
//  PJCore
//
//  Created by Даниил Виноградов on 05.11.2025.
//

import SwiftUI
import UIKit

public extension UIViewController {
    var asView: some View {
        GenericControllerView(self, sizeThatFits: true)
    }

    func asView(sizeThatFits: Bool = true) -> some View {
        GenericControllerView(self, sizeThatFits: sizeThatFits)
    }
}

public extension UIView {
    var asView: some View {
        GenericView(self, sizeThatFits: true)
    }
    
    func asView(sizeThatFits: Bool = true) -> some View {
        GenericView(self, sizeThatFits: sizeThatFits)
    }
}

private struct GenericView<V: UIView>: UIViewRepresentable {
    typealias UIViewType = V

    let view: V
    let sizeThatFits: Bool

    init(_ view: V, sizeThatFits: Bool) {
        self.view = view
        self.sizeThatFits = sizeThatFits
    }

    func makeUIView(context: Context) -> V {
        view
    }
    
    func updateUIView(_ uiView: V, context: Context) { }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: V, context: Context) -> CGSize? {
        sizeThatFits ? uiView.systemLayoutSizeFitting(
            .init(
                width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
                height: proposal.height ?? UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: proposal.width != nil ? .required : .defaultLow,
            verticalFittingPriority: proposal.height != nil ? .required : .defaultLow)
        : nil
    }
}

private struct GenericControllerView<VC: UIViewController>: UIViewControllerRepresentable {
    let controller: VC
    let sizeThatFits: Bool

    init(_ controller: VC, sizeThatFits: Bool) {
        self.controller = controller
        self.sizeThatFits = sizeThatFits
    }

    func makeUIViewController(context: Context) -> VC {
        controller
    }

    func updateUIViewController(_ uiViewController: VC, context: Context) { /* Ignore */ }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: VC, context: Context) -> CGSize? {
        sizeThatFits ? uiViewController.view.intrinsicContentSize : nil
    }
}
