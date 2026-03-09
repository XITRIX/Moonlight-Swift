//
//  StreamingView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

import AVFoundation
import SwiftUI
import VideoToolbox

struct StreamingView: View {
    let app: TemporaryApp

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let config = prepareToStream() {
                StreamingUIView(config: config)
            } else {
                Text("Failed to ferch config")
            }
        }
            .toolbar {
                Button(role: .close) {
                    dismiss()
                }
            }
    }
}

private extension StreamingView {
    func prepareToStream() -> StreamConfiguration? {
        guard let host = app.host.activeAddress,
              let serverCert = app.host.serverCert
        else { return nil }

        let httpsPort = app.host.httpsPort
        let appID = app.id
        let appName = app.name

        let settings = Settings()
        let framerate = settings.framerate

        let bitrate = settings.bitrate
        let width = settings.width
        let height = settings.height
        let playAidioOnPC = settings.playAidioOnPC
        let audioConfig = settings.audioConfig

        let preferredCodec = settings.preferredCodec
        let enableHDR = settings.enableHDR && AVPlayer.eligibleForHDRPlayback
        var supportedVideoFormats = VideoFormat()

        switch preferredCodec {
        case .av1:
            if VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) {
                supportedVideoFormats.insert(.av1Main8)
                if enableHDR {
                    supportedVideoFormats.insert(.av1Main10)
                }
            }
            fallthrough
        case .auto:
            fallthrough
        case .hevc:
            if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
                supportedVideoFormats.insert(.H265)
                if enableHDR {
                    supportedVideoFormats.insert(.h265Main10)
                }
            }
            fallthrough
        case .h264:
            supportedVideoFormats.insert(.H264)
        }

        let config = StreamConfiguration(host: host,
                                         https: httpsPort,
                                         appVersion: "",
                                         gfeVersion: nil,
                                         appID: appID,
                                         appName: appName,
                                         rtspSessionUrl: "",
                                         serverCodecModeSupport: app.host.serverCodecModeSupport,
                                         width: width,
                                         height: height,
                                         frameRate: framerate,
                                         bitRate: bitrate,
                                         riKeyId: Int(arc4random()),
                                         riKey: Utils.randomBytes(16),
                                         gamepadMask: 0x1,
                                         optimizeGameSettings: false,
                                         playAudioOnPC: playAidioOnPC,
                                         swapABXYButtons: false,
                                         audioConfiguration: audioConfig,
                                         supportedVideoFormats: supportedVideoFormats,
                                         multiController: false,
                                         useFramePacing: true,
                                         serverCert: serverCert)

        return config
    }
}

struct StreamingUIView: UIViewRepresentable {
    @State var config: StreamConfiguration

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let streamManager: StreamManager = .init(config: config, renderView: view, connectionCallbacks: context.coordinator)
        context.coordinator.streamManager = streamManager
        Task { await streamManager.start() }

        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: ConnectionCallbacks {
        func connectionStarted() {
            Log.i("Connection started")
        }

        func connectionTerminated(_ errorCode: Int) {
            Log.i("Connection terminated: \(errorCode)")
        }

        func stageStarting(_ stageName: String) {
            Log.i("Starting \(stageName)")
        }

        func stageComplete(_ stageName: String) {
            Log.i("Stage \(stageName) completed")
        }

        func stageFailed(_ stageName: String, withError errorCode: Int, portTestFlags: Int) {
            Log.i("Stage \(stageName) failed")
        }

        func launchFailed(_ message: String) {
            Log.i("Launch failed: \(message)")
        }

        func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {

        }

        func connectionStatusUpdate(_ status: Int) {
            Log.i("Connection status update: \(status)")
        }

        func setHdrMode(_ enabled: Bool) {
            Log.i("Set HDR: \(enabled)")
        }

        func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {

        }

        func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {

        }

        func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {

        }

        func videoContentShown() {

        }

        var streamManager: StreamManager?
    }
}
