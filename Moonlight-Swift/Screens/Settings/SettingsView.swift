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
                Slider(value: .init(get: {
                    Double(settings.bitrate) / 1024
                }, set: { value in
                    settings.bitrate = Int(value * 1024)
                }), in: 5 ... 120, step: 5)
            } header: {
                HStack {
                    Text("Bitrate")
                    Spacer()
                    Text("\(settings.bitrate / 1024) Mbps")
                }
            }

            Section {
                Toggle("Play Audio On PC", isOn: $settings.playAidioOnPC)
                Picker("Preferred Codec", selection: $settings.preferredCodec) {
                    ForEach(Settings.Codec.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                Toggle("Enable HDR", isOn: $settings.enableHDR)
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
    }
}

private extension Settings.Codec {
    var title: String {
        switch self {
        case .auto:
            "Auto"
        case .h264:
            "H.264"
        case .hevc:
            "HEVC"
        case .av1:
            "AV1"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(Settings())
}
