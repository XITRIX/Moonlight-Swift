//
//  StreamManager.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 12/03/2026.
//

import UIKit

class StreamManager {
    init(config: StreamConfiguration, renderView: AVView, connectionCallbacks: ConnectionCallbacks) {
        self.config = config
        self.renderView = renderView
        self.callbacks = connectionCallbacks
        config.riKey = Utils.randomBytes(16)
        config.riKeyId = Int(arc4random())
    }

    private let config: StreamConfiguration
    private let renderView: AVView
    private weak var callbacks: ConnectionCallbacks?
    private var connection: Connection!
}

extension StreamManager {
    func start() async {
        let hMan = HttpManager(hostAddressPortString: config.host, httpsPort: config.https, serverCert: config.serverCert)

        let serverInfoResp = ServerInfoResponse()
        await hMan.executeRequest(.init(for: serverInfoResp, with: hMan.newServerInfoRequest(fastFail: false), fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))

        guard serverInfoResp.isStatusOk else {
            callbacks?.launchFailed(serverInfoResp.statusMessage)
            return
        }

        let pairStatus = serverInfoResp.getStringTag("PairStatus")
        let appversion = serverInfoResp.getStringTag("appversion")
        let gfeVersion = serverInfoResp.getStringTag("GfeVersion")
        let serverState = serverInfoResp.getStringTag("state")

        guard let pairStatus, let appversion, let serverState else {
            callbacks?.launchFailed("Failed to connect to PC")
            return
        }

        guard pairStatus == "1" else {
            callbacks?.launchFailed("Device not paired to PC")
            return
        }

        // Only perform this check on GFE (as indicated by MJOLNIR in state value)
        if (config.width > 4096 || config.height > 4096), serverState.contains("MJOLNIR") {
            // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
            // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
            let codecSupport = serverInfoResp.getStringTag("ServerCodecModeSupport")
            guard let codecSupport, let codecSupportInt = Int(codecSupport), codecSupportInt & 0x200 != 0 else {
                callbacks?.launchFailed("Your host PC's GPU doesn't support streaming video resolutions over 4K.")
                return;
            }
        }

        // Populate the config's version fields from serverinfo
        config.appVersion = appversion
        config.gfeVersion = gfeVersion

        // resumeApp and launchApp handle calling launchFailed
        var sessionUrl: String = ""
        if serverState.hasSuffix("_SERVER_BUSY") {
            // App already running, resume it
            if await !resumeApp(hMan, receiveSessionUrl: &sessionUrl) {
                return;
            }
        } else {
            // Start app
            if await !launchApp(hMan, receiveSessionUrl: &sessionUrl) {
                return;
            }
        }

        // Populate RTSP session URL from launch/resume response
        config.rtspSessionUrl = sessionUrl

        // Initializing the renderer must be done on the main thread
        await MainActor.run {
            let renderer = VideoDecoderRenderer(view: renderView, callbacks: callbacks, streamAspectRatio: Float(CGFloat(config.width) / CGFloat(config.height)), useFramePacing: config.useFramePacing)
            connection = Connection(config: config, renderer: renderer, connectionCallbacks: callbacks)
            let opQueue = OperationQueue()
            opQueue.addOperation(connection)
        }
    }

    func stopStream() {
        connection.terminate()
    }

    func getStatsOverlayText() -> String {
        "To Implement"
    }
}

private extension StreamManager {
    func launchApp(_ hMan: HttpManager, receiveSessionUrl sessionUrl: inout String) async -> Bool {
        let launchResp = HttpResponse()
        await hMan.executeRequest(.init(for: launchResp, with: hMan.newLaunchOrResumeRequest("launch", config: config)))
        let resume = launchResp.getStringTag("gamesession")
        if !launchResp.isStatusOk {
            callbacks?.launchFailed(launchResp.statusMessage)
            Log.e("Failed Launch Response: \(launchResp.statusMessage)")
            return false
        }

        guard let resume, resume != "0" else {
            callbacks?.launchFailed("Failed to launch app")
            Log.e("Failed to parse game session")
            return false
        }

        guard let res = launchResp.getStringTag("sessionUrl0") else {
            callbacks?.launchFailed("Failed to launch app")
            Log.e("Failed to parse game session, sessionUrl0 is empty")
            return false
        }
        sessionUrl = res
        return true
    }

    func resumeApp(_ hMan: HttpManager, receiveSessionUrl sessionUrl: inout String) async -> Bool {
        let resumeResp = HttpResponse()
        await hMan.executeRequest(.init(for: resumeResp, with: hMan.newLaunchOrResumeRequest("resume", config: config)))
        let resume = resumeResp.getStringTag("resume")
        if !resumeResp.isStatusOk {
            callbacks?.launchFailed(resumeResp.statusMessage)
            Log.e("Failed Resume Response: \(resumeResp.statusMessage)")
            return false
        }

        guard let resume, resume != "0" else {
            callbacks?.launchFailed("Failed to resume app")
            Log.e("Failed to parse resume response")
            return false
        }

        guard let res = resumeResp.getStringTag("sessionUrl0") else {
            callbacks?.launchFailed("Failed to resume app")
            Log.e("Failed to parse resume response, sessionUrl0 is empty")
            return false
        }
        sessionUrl = res
        return true
    }
}
