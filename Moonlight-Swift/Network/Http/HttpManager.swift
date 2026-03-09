//
//  HttpManager.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 10/03/2026.
//

import Foundation

class HttpManager {
    init(hostAddressPortString: String, httpsPort: UInt16?, serverCert: Data?) {
        // Use the same UID for all Moonlight clients to allow them
        // quit games started on another Moonlight client.
        uniqueID = "0123456789ABCDEF"
        deviceName = "roth"
        self.serverCert = serverCert

        let address = Utils.addressPortStringToAddress(hostAddressPortString)
        let port = Utils.addressPortStringToPort(hostAddressPortString)

        // If this is an IPv6 literal, we must properly enclose it in brackets
        if address.contains(":") {
            urlSafeHostName = String(format: "[%@]", address)
        } else {
            urlSafeHostName = address
        }

        baseHTTPURL = String(format: "http://%@:%u", urlSafeHostName, port)

        if let httpsPort, httpsPort != 0 {
            baseHTTPSURL = String(format: "https://%@:%u", urlSafeHostName, httpsPort)
        }
    }

    convenience init?(host: TemporaryHost) {
        guard let address = host.activeAddress
        else { return nil }

        self.init(hostAddressPortString: address, httpsPort: host.httpsPort, serverCert: host.serverCert)
        self.host = host
    }

    private lazy var delegates = Delegates(parent: self)

    private var urlSafeHostName: String
    private var baseHTTPURL: String
    private var uniqueID: String
    private var deviceName: String
    private var serverCert: Data?

    private var host: TemporaryHost?
    private var baseHTTPSURL: String?

    private static let SHORT_TIMEOUT_SEC: TimeInterval = 2
    private static let NORMAL_TIMEOUT_SEC: TimeInterval = 5
    private static let LONG_TIMEOUT_SEC: TimeInterval = 60
    private static let EXTRA_LONG_TIMEOUT_SEC: TimeInterval = 180
}

extension HttpManager {
    func setServerCert(_ serverCert: Data) {
        self.serverCert = serverCert
    }

    func ensureHttpsUrlPopulated(fastFail: Bool) async -> Bool {
        guard baseHTTPSURL == nil else { return true }

        if let host, host.httpsPort != 0 {
            baseHTTPSURL = String(format: "https://%@:%u", urlSafeHostName, host.httpsPort)
            return true
        }

        // Query the host to retrieve the HTTPS port
        let serverInfoResponse = ServerInfoResponse()
        await executeRequest(.init(for: serverInfoResponse, with: newHttpServerInfoRequest(fastFail: false)))

        if !serverInfoResponse.isStatusOk {
            return false
        }

        let dummyHost = TemporaryHost()
        serverInfoResponse.populateHost(dummyHost)

        // Pass the port back if the caller provided storage for it
        if let host {
            host.httpsPort = dummyHost.httpsPort
        }

        baseHTTPSURL = String(format: "https://%@:%u", urlSafeHostName, dummyHost.httpsPort)
        return true
    }

    func executeRequest(_ request: HttpRequest) async {
        // This is a special case to handle failure of HTTPS port fetching
        guard let urlRequest = request.request
        else {
            Log.e("HttpRequest is missing for urlRequest")
            return
        }

        var requestResp: Data?
        var respError: NSError?

        Log.d("Making Request: \(request)")

        let config = URLSessionConfiguration.ephemeral
        let urlSession = URLSession(configuration: config, delegate: delegates, delegateQueue: nil)
        defer {
            urlSession.finishTasksAndInvalidate()
        }

        do {
            let (data, response) = try await urlSession.data(for: urlRequest)

            Log.d("Received response: \(response)")

            if let string = String(data: data, encoding: .utf8) {
                Log.d("\n\nReceived data: \(string)\n\n")
                requestResp = HttpManager.fixXmlVersion(xmlData: data)
            } else {
                requestResp = data
            }
        } catch {
            let nsError = error as NSError
            Log.d("Connection error: \(nsError)")
            respError = nsError
        }

        if let requestResp, let response = request.response {
            response.populateWithData(requestResp)

            // If the fallback error code was detected, issue the fallback request
            if response.statusCode == request.fallbackError,
               let fallbackRequest = request.fallbackRequest {
                Log.d("Request failed with fallback error code: \(request.fallbackError ?? -1)")
                request.request = fallbackRequest
                request.fallbackError = 0
                request.fallbackRequest = nil
                await executeRequest(request)
            }
        } else if let respError,
                  respError.domain == NSURLErrorDomain,
                  respError.code == NSURLErrorServerCertificateUntrusted {
            // We must have a pinned cert for HTTPS. If we fail, it must be due to
            // a non-matching cert, not because we had no cert at all.
            assert(serverCert != nil)

            if let fallbackRequest = request.fallbackRequest {
                // This will fall back to HTTP on serverinfo queries to allow us to pair again
                // and get the server cert updated.
                Log.d("Attempting fallback request after certificate trust failure")
                request.request = fallbackRequest
                request.fallbackError = 0
                request.fallbackRequest = nil
                await executeRequest(request)
            }
        } else if let respError, let response = request.response {
            response.statusCode = respError.code
            response.statusMessage = respError.localizedDescription
        }
    }

    func newServerInfoRequest(fastFail: Bool) async -> URLRequest? {
        guard serverCert != nil else {
            // Use HTTP if the cert is not pinned yet
            return newHttpServerInfoRequest(fastFail: fastFail)
        }

        guard await ensureHttpsUrlPopulated(fastFail: fastFail), let baseHTTPSURL else {
            return nil
        }

        let urlString = String(format: "%@/serverinfo?uniqueid=%@", baseHTTPSURL, uniqueID)
        return createRequestFromString(urlString, timeout: fastFail ? Self.SHORT_TIMEOUT_SEC : Self.NORMAL_TIMEOUT_SEC)
    }

    func newHttpServerInfoRequest(fastFail: Bool = false) -> URLRequest {
        let urlString = String(format: "%@/serverinfo", baseHTTPURL)
        return createRequestFromString(urlString, timeout: fastFail ? Self.SHORT_TIMEOUT_SEC : Self.NORMAL_TIMEOUT_SEC)
    }

    func newLaunchOrResumeRequest(_ verb: String, config: StreamConfiguration) async -> URLRequest? {
        guard await ensureHttpsUrlPopulated(fastFail: false), let baseHTTPSURL
        else { return nil }

        // Using an FPS value over 60 causes SOPS to default to 720p60,
        // so force it to 0 to ensure the correct resolution is set. We
        // used to use 60 here but that locked the frame rate to 60 FPS
        // on GFE 3.20.3. We do not do this hack for Sunshine (which is
        // indicated by a negative version in the last field.
        let fps = (config.frameRate > 60 && !config.appVersion.contains(".-")) ? 0 : config.frameRate

        let urlString = String(format: "%@/%@?uniqueid=%@&appid=%@&mode=%dx%dx%d&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d%@&localAudioPlayMode=%d&surroundAudioInfo=%d&remoteControllersBitmap=%d&gcmap=%d&gcpersist=%d%s",
                         baseHTTPSURL, verb, uniqueID,
                         config.appID,
                         config.width, config.height, fps,
                         config.optimizeGameSettings ? 1 : 0,
                               Utils.bytesToHex(config.riKey), config.riKeyId,
                               (config.supportedVideoFormats.rawValue & VideoFormatMask.av1Bit10.rawValue != 0) ? "&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0": "",
                         config.playAudioOnPC ? 1 : 0,
                               SurroundAudioInfoFromAudioConfiguration(config.audioConfiguration.rawValue),
                         config.gamepadMask, config.gamepadMask,
                         !config.multiController ? 1 : 0,
                         LiGetLaunchUrlQueryParameters())
        Log.i("Requesting: \(urlString)")
        return createRequestFromString(urlString, timeout: Self.LONG_TIMEOUT_SEC)
    }

    func newPairRequest(salt: Data, clientCert: Data) -> URLRequest {
        let urlString = String(format: "%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=getservercert&salt=%@&clientcert=%@",
                               baseHTTPURL, uniqueID, deviceName, Utils.bytesToHex(salt), Utils.bytesToHex(clientCert))
        // This call blocks while waiting for the user to input the PIN on the PC
        return createRequestFromString(urlString, timeout: Self.EXTRA_LONG_TIMEOUT_SEC)
    }

    func newUnpairRequest() -> URLRequest {
        let urlString = String(format: "%@/unpair?uniqueid=%@", baseHTTPURL, uniqueID)
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newChallengeRequest(challenge: Data) -> URLRequest {
        let urlString = String(format: "%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientchallenge=%@",
            baseHTTPURL, uniqueID, deviceName, Utils.bytesToHex(challenge))
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newChallengeRespRequest(_ challengeResp: Data) -> URLRequest {
        let urlString = String(format: "%@/pair?uniqueid=%@&devicename=%@&updateState=1&serverchallengeresp=%@",
                               baseHTTPURL, uniqueID, deviceName, Utils.bytesToHex(challengeResp))
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newClientSecretRespRequest(_ clientPairSecret: String) -> URLRequest {
        let urlString = String(format: "%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientpairingsecret=%@", baseHTTPURL, uniqueID, deviceName, clientPairSecret)
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newPairChallenge() async -> URLRequest? {
        guard await ensureHttpsUrlPopulated(fastFail: false), let baseHTTPSURL
        else { return nil }

        let urlString = String(format: "%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=pairchallenge", baseHTTPSURL, uniqueID, deviceName)
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newAppListRequest() async -> URLRequest? {
        guard await ensureHttpsUrlPopulated(fastFail: false), let baseHTTPSURL
        else { return nil }

        let urlString = String(format: "%@/applist?uniqueid=%@", baseHTTPSURL, uniqueID)
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }

    func newAppAssetRequestWithAppId(_ appId: String) async -> URLRequest? {
        guard await ensureHttpsUrlPopulated(fastFail: false), let baseHTTPSURL
        else { return nil }

        let urlString = String(format: "%@/appasset?uniqueid=%@&appid=%@&AssetType=2&AssetIdx=0", baseHTTPSURL, uniqueID, appId)
        return createRequestFromString(urlString, timeout: Self.NORMAL_TIMEOUT_SEC)
    }
}

private extension HttpManager {
    func createRequestFromString(_ urlString: String, timeout: TimeInterval) -> URLRequest {
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return request
    }

    static func fixXmlVersion(xmlData: Data) -> Data {
        guard let xmlString = String(data: xmlData, encoding: .utf8)?.replacingOccurrences(of: "UTF-16", with: "UTF-8", options: [.caseInsensitive]),
              let result = xmlString.data(using: .utf8)
        else { fatalError("Failed to fixXmlVersion") }
        return result
    }

    class Delegates: DelegatesObject<HttpManager>, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            // Allow untrusted server certificates
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let serverTrust = challenge.protectionSpace.serverTrust
            {
                guard SecTrustGetCertificateCount(serverTrust) == 1 else {
                    Log.e("Server certificate count mismatch")
                    return (.performDefaultHandling, nil)
                }

                guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                      let actualCert = certChain.first
                else {
                    Log.e("Server certificate parsing error")
                    return (.performDefaultHandling, nil)
                }

                let actualCertData = SecCertificateCopyData(actualCert) as Data
                guard actualCertData == parent.serverCert else {
                    Log.e("Server certificate mismatch")
                    return (.performDefaultHandling, nil)
                }

                return (.useCredential, URLCredential(trust: serverTrust))
            }

            // Respond to client certificate challenge with our certificate
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
                let identity = getClientCertificate()
                let certArray = getCertificate(identity)
                let newCredential = URLCredential(identity: identity, certificates: certArray, persistence: .permanent)
                return (.useCredential, newCredential)
            }

            return (.performDefaultHandling, nil)
        }

        // Returns an array containing the certificate
        func getCertificate(_ identity: SecIdentity) -> [SecCertificate] {
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(identity, &certificate)
            return [certificate].compactMap { $0 }
        }

        // Returns the identity
        func getClientCertificate() -> SecIdentity {
            let p12Data = CryptoManager.readP12FromFile()

            let options: [String: Any] = [
                kSecImportExportPassphrase as String: "limelight"
            ]

            var items: CFArray?
            let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

            guard status == errSecSuccess else {
                fatalError("Error opening Certificate.")
            }

            guard
                let importedItems = items as? [[String: Any]],
                let firstItem = importedItems.first
            else {
                fatalError("Certificate imported, but identity was not found.")
            }

            return firstItem[kSecImportItemIdentity as String] as! SecIdentity
        }
    }
}

