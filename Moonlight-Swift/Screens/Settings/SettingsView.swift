//
//  SettingsView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 14.03.2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ResolutionPickerView()

                Picker("Framerate", selection: $settings.framerate) {
                    ForEach([30, 60, 120], id: \.self) { value in
                        Text("\(value) FPS").tag(value)
                    }
                }
            }

            Section {
                Toggle("Enable HDR", isOn: $settings.enableHDR)
                Toggle("Play Audio On PC", isOn: $settings.playAidioOnPC)
                Toggle("Touch Controls", isOn: $settings.touchMode)
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(Settings())
}
