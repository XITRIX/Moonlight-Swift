//
//  ConnectionHelper.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

import Foundation

class ConnectionHelper {
    static func getAppListForHost(_ host: TemporaryHost) async -> [TemporaryApp]? {
        guard let hMan = HttpManager(host: host)
        else { return nil }

        // Try up to 5 times to get the app list
        var appListResp: AppListResponse
        for i in 1...5 {
            appListResp = .init(host: host)
            await hMan.executeRequest(.init(for: appListResp, with: hMan.newAppListRequest()))
            guard appListResp.isStatusOk, let appList = appListResp.appList else {
                Log.w("Failed to get applist on try \(i): \(appListResp.statusMessage)")
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            Log.i("App list successfully retreived - took \(i) tries")
            return appList
        }

        return nil
    }

    static func getHostAppAssets(_ appId: String, for host: TemporaryHost) async -> Data? {
        if let asset = getCacheAssetData(for: appId, in: host) {
            return asset
        }

        guard let hMan = HttpManager(host: host)
        else { return nil }

        let appAssetResp = HttpResponse()
        await hMan.executeRequest(.init(for: appAssetResp, with: hMan.newAppAssetRequestWithAppId(appId)))

        guard !appAssetResp.data.isEmpty
        else { return nil }

        setCacheAssetData(appAssetResp.data, for: appId, in: host)
        return appAssetResp.data
    }

    static func pairHost(_ address: String, with pin: String) async -> PairManager.Status? {
        let serverInfoResp = ServerInfoResponse()

        let hMan = HttpManager(hostAddressPortString: address, httpsPort: nil, serverCert: nil)

        await hMan.executeRequest(.init(for: serverInfoResp, with: hMan.newServerInfoRequest(fastFail: false), fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))

        guard serverInfoResp.isStatusOk else {
            Log.w("Failed to get server info: \(serverInfoResp.statusMessage)")
            return .pairFailed(message: "Failed to get server info: \(serverInfoResp.statusMessage)")
        }

        let host = TemporaryHost()
        serverInfoResp.populateHost(host)
        if host.pairState == .paired {
            Log.i("Already paired")
            return .alreadyPaired
        }

        let pMan = PairManager(httpManager: hMan, clientCert: CryptoManager.readCertFromFile())
        return .alreadyPaired
//        return await pMan.startPairing(with: pin)
    }
}

private extension ConnectionHelper {
    private static func getCacheAssetData(for appId: String, in host: TemporaryHost) -> Data? {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }

        let assetPath = cacheDirectory.appending(path: "assets/\(host.uuid)/\(appId).png")
        return try? Data(contentsOf: assetPath, options: .mappedIfSafe)
    }

    private static func setCacheAssetData(_ data: Data, for appId: String, in host: TemporaryHost) {
        guard let cacheAssetsDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "assets")
        else { return }

        if !FileManager.default.fileExists(atPath: cacheAssetsDirectory.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: cacheAssetsDirectory, withIntermediateDirectories: true)
        }

        let assetPath = cacheAssetsDirectory.appending(path: "\(host.uuid)/\(appId).png")
        try? data.write(to: assetPath)
    }
}
