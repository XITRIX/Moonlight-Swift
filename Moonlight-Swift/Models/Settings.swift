//
//  Settings.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 12/03/2026.
//

import SwiftData

@Model
class Settings {
    var bitrate: Int
    var framerate: Int
    var height: Int
    var width: Int
    private var resolutionPresetRawValue: String
    private var audioConfigRawValue: Int32
    private var preferredCodecRawValue: String
    var playAidioOnPC: Bool
    var enableHDR: Bool
    var touchMode: Bool

    init(bitrate: Int = 25 * 1024,
         framerate: Int = 60,
         resolutionPreset: Resolution = .p1080,
         height: Int = 1080,
         width: Int = 1920,
         audioConfig: AudioConfiguration = .stereo,
         preferredCodec: Codec = .auto,
         playAidioOnPC: Bool = false,
         enableHDR: Bool = false,
         touchMode: Bool = false)
    {
        self.bitrate = bitrate
        self.framerate = framerate
        self.height = height
        self.width = width
        self.resolutionPresetRawValue = resolutionPreset.rawValue
        self.audioConfigRawValue = audioConfig.rawValue
        self.preferredCodecRawValue = preferredCodec.rawValue
        self.playAidioOnPC = playAidioOnPC
        self.enableHDR = enableHDR
        self.touchMode = touchMode
    }
}

extension Settings {
    var resolutionPreset: Resolution {
        get { Resolution(rawValue: resolutionPresetRawValue) ?? .p1080 }
        set { resolutionPresetRawValue = newValue.rawValue }
    }

    var audioConfig: AudioConfiguration {
        get { AudioConfiguration(rawValue: audioConfigRawValue) ?? .stereo }
        set { audioConfigRawValue = newValue.rawValue }
    }

    var preferredCodec: Codec {
        get { Codec(rawValue: preferredCodecRawValue) ?? .auto }
        set { preferredCodecRawValue = newValue.rawValue }
    }
}

extension Settings {
    nonisolated
    enum Codec: String, Identifiable, Codable, CaseIterable {
        var id: Self { self }
        case auto
        case h264
        case hevc
        case av1
    }
}

extension Settings {
    nonisolated
    enum Resolution: String, Identifiable, Codable, Hashable {
        var id: Self { self }
        case p360
        case p720
        case p1080
        case p4k
        case safeArea
        case native
        case custom
    }

    var resolution: (width: Int, height: Int)? {
        switch resolutionPreset {
        case .p360:
            return (width: 480, height: 360)
        case .p720:
            return (width: 1280, height: 720)
        case .p1080:
            return (width: 1920, height: 1080)
        case .p4k:
            return (width: 3840, height: 2160)
        case .safeArea:
            return nil
        case .native:
            return nil
        case .custom:
            return (width: width, height: height)
        }
    }
}

nonisolated
extension AudioConfiguration: Identifiable, Codable {
    public var id: Self { self }
}
