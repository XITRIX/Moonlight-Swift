//
//  StreamConfiguration.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 12/03/2026.
//

import Foundation

@objcMembers
class StreamConfiguration: NSObject {
    var host: String
    var https: UInt16
    var appVersion: String
    var gfeVersion: String?
    var appID: String
    var appName: String
    var rtspSessionUrl: String?
    var serverCodecModeSupport: Int32
    var width: Int
    var height: Int
    var frameRate: Int
    var bitRate: Int
    var riKeyId: Int
    var riKey: Data
    var gamepadMask: Int
    var optimizeGameSettings: Bool
    var playAudioOnPC: Bool
    var swapABXYButtons: Bool
    var audioConfiguration: AudioConfiguration
    var supportedVideoFormats: VideoFormat
    var multiController: Bool
    var useFramePacing: Bool
    var serverCert: Data

    init(host: String,
         https: UInt16,
         appVersion: String,
         gfeVersion: String? = nil,
         appID: String,
         appName: String,
         rtspSessionUrl: String? = nil,
         serverCodecModeSupport: Int32,
         width: Int,
         height: Int,
         frameRate: Int,
         bitRate: Int,
         riKeyId: Int,
         riKey: Data,
         gamepadMask: Int,
         optimizeGameSettings: Bool,
         playAudioOnPC: Bool,
         swapABXYButtons: Bool,
         audioConfiguration: AudioConfiguration,
         supportedVideoFormats: VideoFormat,
         multiController: Bool,
         useFramePacing: Bool,
         serverCert: Data)
    {
        self.host = host
        self.https = https
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.appID = appID
        self.appName = appName
        self.rtspSessionUrl = rtspSessionUrl
        self.serverCodecModeSupport = serverCodecModeSupport
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitRate = bitRate
        self.riKeyId = riKeyId
        self.riKey = riKey
        self.gamepadMask = gamepadMask
        self.optimizeGameSettings = optimizeGameSettings
        self.playAudioOnPC = playAudioOnPC
        self.swapABXYButtons = swapABXYButtons
        self.audioConfiguration = audioConfiguration
        self.supportedVideoFormats = supportedVideoFormats
        self.multiController = multiController
        self.useFramePacing = useFramePacing
        self.serverCert = serverCert
        super.init()
    }
}
