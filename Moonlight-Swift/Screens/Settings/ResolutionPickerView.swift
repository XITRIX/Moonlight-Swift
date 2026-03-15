//
//  ResolutionPickerView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 15.03.2026.
//

import SwiftUI

struct ResolutionPickerView: View {
    @Environment(Settings.self) private var settings

    @State private var showCustomResolutionPicker: Bool = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""

    private let resolutions: [Settings.Resolution] = [
        .p360,
        .p720,
        .p1080,
        .p4k,
        .native,
        .custom
    ]

    var body: some View {
        Picker("Resolution", selection: resolutionBinding(for: settings)) {
            ForEach(resolutions) { preset in
                Text(settings.resolutionTitle(for: preset)).tag(preset)
            }
        }
        .alert("Custom resolution", isPresented: $showCustomResolutionPicker) {
            TextField("Width", text: $customWidth)
            TextField("Height", text: $customHeight)
            Button("Cancel", role: .cancel) {
                showCustomResolutionPicker = false
            }
            Button("Done") {
                guard let width = Int(customWidth),
                      let height = Int(customHeight)
                else { return }
                settings.width = width
                settings.height = height
                settings.resolutionPreset = .custom
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private extension ResolutionPickerView {
    func resolutionBinding(for settings: Settings) -> Binding<Settings.Resolution> {
        Binding(
            get: {
                settings.resolutionPreset
            },
            set: { preset in
                if preset == .custom {
                    showCustomResolutionPicker = true
                    return
                }
                settings.resolutionPreset = preset
            }
        )
    }
}

private extension Settings {
    func resolutionTitle(for preset: Resolution) -> String {
        switch preset {
        case .p360:
            return "360p"
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .p4k:
            return "4K"
        case .safeArea:
            return "Safe Area"
        case .native:
            return "Full Screen"
        case .custom:
            if width == 0 || height == 0 {
                return "Custom"
            }
            return "Custom (\(width)x\(height))"
        }
    }
}
