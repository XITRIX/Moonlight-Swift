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
        panGestureRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(panGestureRecognizer)

        let scrollGestureRecognizer = UIPanGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.scrollRecognizer(_:)))
        scrollGestureRecognizer.minimumNumberOfTouches = 2
        scrollGestureRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollGestureRecognizer)

        let leftClickGestureRecognizer = UITapGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.leftClickRecognizer(_:)))
        leftClickGestureRecognizer.numberOfTouchesRequired = 1
        view.addGestureRecognizer(leftClickGestureRecognizer)

        let leftDragGestureRecognizer = UILongPressGestureRecognizer(target: context.coordinator,
                                                                     action: #selector(Coordinator.leftDragRecognizer(_:)))
        leftDragGestureRecognizer.numberOfTouchesRequired = 1
        leftDragGestureRecognizer.numberOfTapsRequired = 2
        leftDragGestureRecognizer.minimumPressDuration = 0
        leftDragGestureRecognizer.allowableMovement = .greatestFiniteMagnitude
        leftDragGestureRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(leftDragGestureRecognizer)

        leftClickGestureRecognizer.require(toFail: leftDragGestureRecognizer)

        let rightClickGestureRecognizer = UITapGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.rightClickRecognizer(_:)))
        rightClickGestureRecognizer.numberOfTouchesRequired = 2
        view.addGestureRecognizer(rightClickGestureRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var isLeftButtonHeld = false

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

        @objc func leftClickRecognizer(_ recognizer: UITapGestureRecognizer) {
            LiSendMouseButtonEvent(ButtonAction.press.rawValue, MouseButton.left.rawValue)
            LiSendMouseButtonEvent(ButtonAction.release.rawValue, MouseButton.left.rawValue)
        }

        @objc func leftDragRecognizer(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard !isLeftButtonHeld else { return }
                isLeftButtonHeld = true
                LiSendMouseButtonEvent(ButtonAction.press.rawValue, MouseButton.left.rawValue)
            case .ended, .cancelled, .failed:
                guard isLeftButtonHeld else { return }
                isLeftButtonHeld = false
                LiSendMouseButtonEvent(ButtonAction.release.rawValue, MouseButton.left.rawValue)
            default:
                break
            }
        }

        @objc func rightClickRecognizer(_ recognizer: UITapGestureRecognizer) {
            LiSendMouseButtonEvent(ButtonAction.press.rawValue, MouseButton.left.rawValue)
            LiSendMouseButtonEvent(ButtonAction.release.rawValue, MouseButton.left.rawValue)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let isPanAndHoldPair =
                (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer) ||
                (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)

            return isPanAndHoldPair
        }
    }
}
