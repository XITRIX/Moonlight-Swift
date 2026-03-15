//
//  TouchInputOverlayView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 18.08.2025.
//

import SwiftUI
import UIKit

struct TouchInputOverlayView: View {
    var body: some View {
        TouchResponderView()
            .ignoresSafeArea()
    }
}

private struct TouchResponderView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let panGestureRecognizer = UIPanGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.panRecognizer(_:)))
        panGestureRecognizer.minimumNumberOfTouches = 1
        panGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panGestureRecognizer)

        let scrollGestureRecognizer = UIPanGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.scrollRecognizer(_:)))
        scrollGestureRecognizer.minimumNumberOfTouches = 2
        scrollGestureRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollGestureRecognizer)

        let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.tapRecognizer(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        @objc func panRecognizer(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            LiSendMouseMoveEvent(Int16(translation.x), Int16(translation.y))
        }

        @objc func scrollRecognizer(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)

            LiSendHighResScrollEvent(Int16(translation.y))
            LiSendHighResHScrollEvent(Int16(translation.x))
        }

        @objc func tapRecognizer(_ recognizer: UITapGestureRecognizer) {
            LiSendMouseButtonEvent(ButtonAction.press.rawValue, MouseButton.left.rawValue)
            LiSendMouseButtonEvent(ButtonAction.release.rawValue, MouseButton.left.rawValue)
        }
    }
}
