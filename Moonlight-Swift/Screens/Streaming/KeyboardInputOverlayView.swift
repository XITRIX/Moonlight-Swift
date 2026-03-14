//
//  KeyboardInputOverlayView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 14.03.2026.
//

import SwiftUI
import UIKit

struct KeyboardInputOverlayView: View {
    var body: some View {
        KeyboardResponderField()
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }
}

private struct KeyboardResponderField: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> KeyboardInputTextField {
        let textField = KeyboardInputTextField()
        textField.delegate = context.coordinator
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.smartQuotesType = .no
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .done
        textField.tintColor = .clear
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.onDeleteBackward = {
            context.coordinator.sendBackspace()
        }
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
        return textField
    }

    func updateUIView(_ uiView: KeyboardInputTextField, context: Context) {
        if !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    static func dismantleUIView(_ uiView: KeyboardInputTextField, coordinator: Coordinator) {
        uiView.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                sendBackspace()
                return false
            }

            for character in string {
                sendCharacter(character)
            }

            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            sendKey(.returnKey)
            return false
        }

        func sendBackspace() {
            sendKey(.backspace)
        }

        private func sendCharacter(_ character: Character) {
            guard let mapping = KeyMapping(character: character) else { return }
            sendKey(mapping.keyCode, modifiers: mapping.modifiers)
        }

        private func sendKey(_ key: SpecialKey) {
            sendKey(key.keyCode, modifiers: 0)
        }

        private func sendKey(_ keyCode: Int16, modifiers: Int8 = 0) {
            LiSendKeyboardEvent(keyCode, KeyboardEventAction.down.rawValue, modifiers)
            LiSendKeyboardEvent(keyCode, KeyboardEventAction.up.rawValue, modifiers)
        }
    }
}

private final class KeyboardInputTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
    }
}

private enum KeyboardEventAction: Int8 {
    case down = 0x03
    case up = 0x04
}

private enum KeyboardModifier: Int8 {
    case shift = 0x01
}

private enum SpecialKey {
    case backspace
    case returnKey

    var keyCode: Int16 {
        switch self {
        case .backspace:
            0x08
        case .returnKey:
            0x0D
        }
    }
}

private struct KeyMapping {
    let keyCode: Int16
    let modifiers: Int8

    init?(character: Character) {
        switch character {
        case "a"..."z":
            guard let scalar = character.unicodeScalars.first else { return nil }
            keyCode = Int16(scalar.value - 32)
            modifiers = 0
        case "A"..."Z":
            guard let scalar = character.unicodeScalars.first else { return nil }
            keyCode = Int16(scalar.value)
            modifiers = KeyboardModifier.shift.rawValue
        case "0"..."9":
            guard let scalar = character.unicodeScalars.first else { return nil }
            keyCode = Int16(scalar.value)
            modifiers = 0
        case " ":
            keyCode = 0x20
            modifiers = 0
        case "\n":
            keyCode = 0x0D
            modifiers = 0
        case "-":
            keyCode = 0xBD
            modifiers = 0
        case "_":
            keyCode = 0xBD
            modifiers = KeyboardModifier.shift.rawValue
        case "=":
            keyCode = 0xBB
            modifiers = 0
        case "+":
            keyCode = 0xBB
            modifiers = KeyboardModifier.shift.rawValue
        case "[":
            keyCode = 0xDB
            modifiers = 0
        case "{":
            keyCode = 0xDB
            modifiers = KeyboardModifier.shift.rawValue
        case "]":
            keyCode = 0xDD
            modifiers = 0
        case "}":
            keyCode = 0xDD
            modifiers = KeyboardModifier.shift.rawValue
        case "\\":
            keyCode = 0xDC
            modifiers = 0
        case "|":
            keyCode = 0xDC
            modifiers = KeyboardModifier.shift.rawValue
        case ";":
            keyCode = 0xBA
            modifiers = 0
        case ":":
            keyCode = 0xBA
            modifiers = KeyboardModifier.shift.rawValue
        case "'":
            keyCode = 0xDE
            modifiers = 0
        case "\"":
            keyCode = 0xDE
            modifiers = KeyboardModifier.shift.rawValue
        case ",":
            keyCode = 0xBC
            modifiers = 0
        case "<":
            keyCode = 0xBC
            modifiers = KeyboardModifier.shift.rawValue
        case ".":
            keyCode = 0xBE
            modifiers = 0
        case ">":
            keyCode = 0xBE
            modifiers = KeyboardModifier.shift.rawValue
        case "/":
            keyCode = 0xBF
            modifiers = 0
        case "?":
            keyCode = 0xBF
            modifiers = KeyboardModifier.shift.rawValue
        case "`":
            keyCode = 0xC0
            modifiers = 0
        case "~":
            keyCode = 0xC0
            modifiers = KeyboardModifier.shift.rawValue
        case "!":
            keyCode = 0x31
            modifiers = KeyboardModifier.shift.rawValue
        case "@":
            keyCode = 0x32
            modifiers = KeyboardModifier.shift.rawValue
        case "#":
            keyCode = 0x33
            modifiers = KeyboardModifier.shift.rawValue
        case "$":
            keyCode = 0x34
            modifiers = KeyboardModifier.shift.rawValue
        case "%":
            keyCode = 0x35
            modifiers = KeyboardModifier.shift.rawValue
        case "^":
            keyCode = 0x36
            modifiers = KeyboardModifier.shift.rawValue
        case "&":
            keyCode = 0x37
            modifiers = KeyboardModifier.shift.rawValue
        case "*":
            keyCode = 0x38
            modifiers = KeyboardModifier.shift.rawValue
        case "(":
            keyCode = 0x39
            modifiers = KeyboardModifier.shift.rawValue
        case ")":
            keyCode = 0x30
            modifiers = KeyboardModifier.shift.rawValue
        default:
            return nil
        }
    }
}

#Preview {
    KeyboardInputOverlayView()
}
