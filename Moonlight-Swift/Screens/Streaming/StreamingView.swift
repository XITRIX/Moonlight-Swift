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
    @State private var selection = "Touch"
    @State private var closeSessionPresented = false

    var body: some View {
        Group {
            if let config = prepareToStream() {
                StreamingScreenView(config: config)
                    .ignoresSafeArea()
            } else {
                Text("Failed to ferch config")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Controls", selection: $selection) {
                    Image(systemName: "hand.draw").tag("Touch")
                    Image(systemName: "keyboard").tag("Keyboard")
                    Image(systemName: "gamecontroller").tag("Gamepad")
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(role: .close) {
                    closeSessionPresented = true
                }
                .confirmationDialog("Close session", isPresented: $closeSessionPresented) {
                    Button("Disconnect") {
                        dismiss()
                    }
                    Button("Terminate", role: .destructive) {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
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
}

struct StreamingScreenView: UIViewRepresentable {
    let config: StreamConfiguration

    func makeUIView(context: Context) -> AVView {
        let view = AVView()

        let streamManager: StreamManager = .init(config: config, renderView: view, connectionCallbacks: context.coordinator)
        context.coordinator.streamManager = streamManager
        Task { await streamManager.start() }

        // MARK: Pan recognizer
        let panGestureRecognizer = UIPanGestureRecognizer()
        panGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.panRecognizer(_:)))
        view.addGestureRecognizer(panGestureRecognizer)

        // MARK: Tap recognizer
        let tapGestureRecognizer = UITapGestureRecognizer()
        tapGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.tapRecognizer(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        context.coordinator.controllerBridge.start()

        return view
    }

    func updateUIView(_ uiView: AVView, context: Context) {}

    static func dismantleUIView(_ uiView: AVView, coordinator: Coordinator) {
        coordinator.controllerBridge.stop()
        coordinator.streamManager?.stopStream()
        coordinator.streamManager = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        fileprivate let controllerBridge: ControllerBridge = .init()
        fileprivate var streamManager: StreamManager?
    }
}

extension StreamingScreenView.Coordinator {
    @objc func panRecognizer(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let translation = recognizer.translation(in: view)
        recognizer.setTranslation(.zero, in: view)
        LiSendMouseMoveEvent(Int16(translation.x), Int16(translation.y))
    }

    @objc func tapRecognizer(_ recognizer: UITapGestureRecognizer) {
        LiSendMouseButtonEvent(ButtonAction.press.rawValue, MouseButton.left.rawValue)
        LiSendMouseButtonEvent(ButtonAction.release.rawValue, MouseButton.left.rawValue)
    }
}

extension StreamingScreenView.Coordinator: ConnectionCallbacks {
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
