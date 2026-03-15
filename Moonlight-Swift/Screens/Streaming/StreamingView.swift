//
//  StreamingView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

import AVFoundation
import SwiftUI
import UIKit
import VideoToolbox

extension StreamingView {
    enum ImputMode {
        case touch
        case keyboard
        case gamepad
    }
}

struct StreamingView: View {
    let app: TemporaryApp

    @Environment(\.dismiss) private var dismiss
    @Environment(Settings.self) private var settings
    
    @State private var inputMode: ImputMode = .touch
    @State private var closeSessionPresented = false
    @State private var terminating: Bool = false

    var body: some View {
        Group {
            if let config = prepareToStream() {
                StreamingScreenView(config: config)
            } else {
                Text("Failed to ferch config")
            }
        }
        .overlay {
            inputOverlay
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Controls", selection: $inputMode) {
                    Image(systemName: "hand.draw").tag(ImputMode.touch)
                    Image(systemName: "keyboard").tag(ImputMode.keyboard)
                    Image(systemName: "gamecontroller").tag(ImputMode.gamepad)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(role: .close) {
                    closeSessionPresented = true
                }
                .disabled(terminating)
                .confirmationDialog("Close session", isPresented: $closeSessionPresented) {
                    Button("Disconnect") {
                        dismiss()
                    }
                    Button("Terminate", role: .destructive) {
                        Task {
                            terminating = true
                            defer { dismiss() }
                            guard let hMan = HttpManager(host: app.host) else { return }
                            let quitResponse = HttpResponse()
                            try await hMan.executeRequest(.init(for: quitResponse, with: hMan.newQuitAppRequest()))
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
}

private extension StreamingView {
    @ViewBuilder
    var inputOverlay: some View {
        ZStack {
            switch inputMode {
            case .touch:
                TouchInputOverlayView()
            case .keyboard:
                TouchInputOverlayView()
                KeyboardInputOverlayView()
            case .gamepad:
                EmptyView()
            }
        }
    }

    func prepareToStream() -> StreamConfiguration? {
        guard let host = app.host.activeAddress,
              let serverCert = app.host.serverCert
        else { return nil }

        let httpsPort = app.host.httpsPort
        let appID = app.id
        let appName = app.name

        let framerate = settings.framerate

        let bitrate = settings.bitrate

        let width: Int
        let height: Int

        if let resolution = settings.resolution {
            (width, height) = resolution
        } else {
            if settings.resolutionPreset == .native,
               let nativeResolution = currentScreenResolution()
            {
                (width, height) = nativeResolution
            } else {
                width = settings.width
                height = settings.height
            }
        }

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

        return StreamConfiguration(host: host,
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
    }

    func currentScreenResolution() -> (width: Int, height: Int)? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?
            .keyWindow

        guard let window else {
            return nil
        }

        let rawBounds = window.bounds

        let rawWidth = window.bounds.width * window.layer.contentsScale
        let rawHeight = window.bounds.height * window.layer.contentsScale

        let width = max(rawWidth, rawHeight)
        let height = min(rawWidth, rawHeight)

        return (width: Int(width), height: Int(height))
    }
}

struct StreamingScreenView: View {
    let config: StreamConfiguration

    var body: some View {
        StreamingScreenViewRepresentation(config: config)
            .ignoresSafeArea()
    }
}

struct StreamingScreenViewRepresentation: UIViewRepresentable {
    let config: StreamConfiguration

    func makeUIView(context: Context) -> UIView {
        let view = AVView()

        let streamManager: StreamManager = .init(config: config, renderView: view, connectionCallbacks: context.coordinator)
        context.coordinator.streamManager = streamManager
        Task { await streamManager.start() }

        context.coordinator.controllerBridge.start()
#if !os(visionOS)
        Air.play(view)
#endif

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controllerBridge.stop()
        coordinator.streamManager?.stopStream()
        coordinator.streamManager = nil
#if !os(visionOS)
        Air.stop()
#endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        fileprivate let controllerBridge: ControllerBridge = .init()
        fileprivate var streamManager: StreamManager?
    }
}

extension StreamingScreenViewRepresentation.Coordinator: ConnectionCallbacks {
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

    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {}

    func connectionStatusUpdate(_ status: Int) {
        Log.i("Connection status update: \(status)")
    }

    func setHdrMode(_ enabled: Bool) {
        Log.i("Set HDR: \(enabled)")
    }

    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {}

    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {}

    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {}

    func videoContentShown() {}
}


class AVView: UIView {
    var avLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        avLayer.videoGravity = .resizeAspect
    }
}
