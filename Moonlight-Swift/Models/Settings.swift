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
    var audioConfig: AudioConfiguration
    var preferredCodec: Codec
    var playAidioOnPC: Bool
    var enableHDR: Bool
    var touchMode: Bool

    init(bitrate: Int = 50 * 1024,
         framerate: Int = 60,
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
        self.audioConfig = audioConfig
        self.preferredCodec = preferredCodec
        self.playAidioOnPC = playAidioOnPC
        self.enableHDR = enableHDR
        self.touchMode = touchMode
    }
}

extension Settings {
    nonisolated
    enum Codec: Identifiable, Codable {
        var id: Self { self }
        case auto
        case h264
        case hevc
        case av1
    }
}

nonisolated
extension AudioConfiguration: Identifiable, Codable {
    public var id: Self { self }
}
