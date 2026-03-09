//
//  PairManager.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 10.03.2026.
//

import Foundation
import UIKit

class PairManager {
    enum Status {
//        case startPairing(pin: String)
        case pairSuccessful(serverCert: Data)
        case pairFailed(message: String)
        case alreadyPaired
    }

    init(httpManager: HttpManager, clientCert: Data) {
        self.httpManager = httpManager
        self.clientCert = clientCert
    }

    private let httpManager: HttpManager
    private let clientCert: Data
}

extension PairManager {
    func startPairing(with pin: String) async -> Status {
//        let pin = Self.generatePin()
        Log.d("Start pairing with pin: \(pin)")
//        return .startPairing(pin: pin)

        let serverInfoResp = ServerInfoResponse()
        await httpManager.executeRequest(.init(for: serverInfoResp, with: httpManager.newServerInfoRequest(fastFail: false), fallbackError: 401, fallbackRequest: httpManager.newHttpServerInfoRequest()))

        guard serverInfoResp.isStatusOk else {
            return .pairFailed(message: serverInfoResp.statusMessage)
        }

        guard serverInfoResp.getStringTag("PairStatus") != "1" else {
            return .alreadyPaired
        }

        guard let appVersion = serverInfoResp.getStringTag("appversion"),
              let state = serverInfoResp.getStringTag("state")
        else {
            return .pairFailed(message: "Missing XML element")
        }

        return await initiatePair(withPin: pin,
                     forServerMajorVersion: Int(String(appVersion.first ?? "0")) ?? 0,
                     state: state)
    }

    func finishPairing(bgId: UIBackgroundTaskIdentifier, forResponse resp: HttpResponse, withFallbackError errorMsg: String) async -> Status {
        await httpManager.executeRequest(.init(with: httpManager.newUnpairRequest()))

        if bgId != .invalid {
            UIApplication.shared.endBackgroundTask(bgId)
        }

        var errorMsg = errorMsg

        if !resp.isStatusOk {
            errorMsg = resp.statusMessage
        }

        return .pairFailed(message: errorMsg)
    }

    func finishPairing(bgId: UIBackgroundTaskIdentifier, withSuccess derCertBytes: Data) -> Status {
        if bgId != .invalid {
            UIApplication.shared.endBackgroundTask(bgId)
        }

        return .pairSuccessful(serverCert: derCertBytes)
    }

    func initiatePair(withPin pin: String, forServerMajorVersion serverMajorVersion: Int, state: String) async -> Status {
        Log.i("Pairing with generation \(serverMajorVersion) server in state \(state)");

        // Start a background task to help prevent the app from being killed
        // while pairing is in progress.
        let bgId = UIApplication.shared.beginBackgroundTask(withName: "Pairing PC") {
            Log.w("Background pairing time has expired!")
        }

        let salt = Utils.randomBytes(16)
        let saltedPIN = Self.concatData(salt, with: Data(pin.utf8))

        Log.i("PIN: \(pin), salt \(salt)")

        let pairResp = HttpResponse()
        await httpManager.executeRequest(
            HttpRequest(
                for: pairResp,
                with: httpManager.newPairRequest(salt: salt, clientCert: clientCert)
            )
        )

        Log.i("Pairing Stage #1")
        if !Self.verifyResponseStatus(pairResp) {
            // GFE does not allow pairing while a server is busy, but Sunshine does.
            // We give it a try and display the busy error if it fails.
            if state.hasSuffix("_SERVER_BUSY") {
                return await finishPairing(
                    bgId: bgId,
                    forResponse: pairResp,
                    withFallbackError: "You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again."
                )
            } else {
                return await finishPairing(
                    bgId: bgId,
                    forResponse: pairResp,
                    withFallbackError: "Pairing was declined by the target."
                )
            }
        }

        Log.i("Pairing Stage #2")
        guard let plainCert = pairResp.getStringTag("plaincert"), !plainCert.isEmpty else {
            return await finishPairing(
                bgId: bgId,
                forResponse: pairResp,
                withFallbackError: "Another pairing attempt is already in progress."
            )
        }

        Log.i("Pairing Stage #3")
        // Pin the cert for TLS usage on this host
        let plainCertBytes = Utils.hexToBytes(plainCert)
        guard let derCertBytes = CryptoManager.pemToDer(plainCertBytes) else {
            return await finishPairing(
                bgId: bgId,
                forResponse: pairResp,
                withFallbackError: "Failed to parse server certificate."
            )
        }

        Log.i("Pairing Stage #4")
        httpManager.setServerCert(derCertBytes)

        let cryptoMan = CryptoManager()

        let aesKey: Data
        let hashLength: Int

        Log.i("Pairing Stage #5")
        // Gen 7 servers use SHA256 to get the key
        if serverMajorVersion >= 7 {
            aesKey = cryptoMan.createAESKeyFromSaltSHA256(saltedPIN)
            hashLength = 32
        } else {
            aesKey = cryptoMan.createAESKeyFromSaltSHA1(saltedPIN)
            hashLength = 20
        }

        Log.i("Pairing Stage #6")
        let randomChallenge = Utils.randomBytes(16)
        let encryptedChallenge = cryptoMan.aesEncrypt(randomChallenge, withKey: aesKey)

        let challengeResp = HttpResponse()
        await httpManager.executeRequest(
            HttpRequest(
                for: challengeResp,
                with: httpManager.newChallengeRequest(challenge: encryptedChallenge)
            )
        )

        Log.i("Pairing Stage #7")
        if !Self.verifyResponseStatus(challengeResp) {
            return await finishPairing(bgId: bgId, forResponse: challengeResp, withFallbackError: "Pairing stage #2 failed")
        }

        guard let challengeResponseHex = challengeResp.getStringTag("challengeresponse") else {
            return await finishPairing(bgId: bgId, forResponse: challengeResp, withFallbackError: "Pairing stage #2 failed")
        }

        Log.i("Pairing Stage #8")
        let encServerChallengeResp = Utils.hexToBytes(challengeResponseHex)
        let decServerChallengeResp = cryptoMan.aesDecrypt(data: encServerChallengeResp, key: aesKey)

        guard decServerChallengeResp.count >= hashLength + 16 else {
            return await finishPairing(bgId: bgId, forResponse: challengeResp, withFallbackError: "Pairing stage #2 failed")
        }

        Log.i("Pairing Stage #9")
        let serverResponse = decServerChallengeResp.subdata(in: 0..<hashLength)
        let serverChallenge = decServerChallengeResp.subdata(in: hashLength..<(hashLength + 16))

        let clientSecret = Utils.randomBytes(16)

        guard let clientCertSignature = CryptoManager.getSignatureFromCert(clientCert) else {
            return await finishPairing(bgId: bgId, forResponse: challengeResp, withFallbackError: "Client certificate invalid")
        }

        Log.i("Pairing Stage #10")
        let challengeRespHashInput = Self.concatData(
            Self.concatData(serverChallenge, with: clientCertSignature),
            with: clientSecret
        )

        let challengeRespHash: Data
        if serverMajorVersion >= 7 {
            challengeRespHash = cryptoMan.SHA256Hash(data: challengeRespHashInput)
        } else {
            challengeRespHash = cryptoMan.SHA1Hash(data: challengeRespHashInput)
        }

        var paddedHash = challengeRespHash
        paddedHash.count = 32

        let challengeRespEncrypted = cryptoMan.aesEncrypt(paddedHash, withKey: aesKey)

        Log.i("Pairing Stage #11")
        let secretResp = HttpResponse()
        await httpManager.executeRequest(
            HttpRequest(
                for: secretResp,
                with: httpManager.newChallengeRespRequest(challengeRespEncrypted)
            )
        )

        Log.i("Pairing Stage #12")
        guard Self.verifyResponseStatus(secretResp),
              let pairingSecretHex = secretResp.getStringTag("pairingsecret")
        else {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Pairing stage #3 failed")
        }

        let serverSecretResp = Utils.hexToBytes(pairingSecretHex)
        guard serverSecretResp.count >= 16 else {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Pairing stage #3 failed")
        }

        Log.i("Pairing Stage #13")
        let serverSecret = serverSecretResp.subdata(in: 0..<16)
        let serverSignature = serverSecretResp.subdata(in: 16..<serverSecretResp.count)

        if !cryptoMan.verifySignature(data: serverSecret, signature: serverSignature, cert: plainCertBytes) {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Server certificate invalid")
        }

        guard let serverCertSignature = CryptoManager.getSignatureFromCert(plainCertBytes) else {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Server certificate invalid")
        }

        Log.i("Pairing Stage #14")
        let serverChallengeRespHashInput = Self.concatData(
            Self.concatData(randomChallenge, with: serverCertSignature),
            with: serverSecret
        )

        let serverChallengeRespHash: Data
        if serverMajorVersion >= 7 {
            serverChallengeRespHash = cryptoMan.SHA256Hash(data: serverChallengeRespHashInput)
        } else {
            serverChallengeRespHash = cryptoMan.SHA1Hash(data: serverChallengeRespHashInput)
        }

        if serverChallengeRespHash != serverResponse {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Incorrect PIN")
        }

        Log.i("Pairing Stage #15")
        let privateKey = CryptoManager.readKeyFromFile()
        guard let signedClientSecret = cryptoMan.signData(clientSecret, withKey: privateKey) else {
            return await finishPairing(bgId: bgId, forResponse: secretResp, withFallbackError: "Failed to sign client secret")
        }

        let clientPairingSecret = Self.concatData(clientSecret, with: signedClientSecret)

        Log.i("Pairing Stage #16")
        let clientSecretResp = HttpResponse()
        await httpManager.executeRequest(
            HttpRequest(
                for: clientSecretResp,
                with: httpManager.newClientSecretRespRequest(Utils.bytesToHex(clientPairingSecret))
            )
        )

        if !Self.verifyResponseStatus(clientSecretResp) {
            return await finishPairing(bgId: bgId, forResponse: clientSecretResp, withFallbackError: "Pairing stage #4 failed")
        }

        Log.i("Pairing Stage #17")
        let clientPairChallengeResp = HttpResponse()
        await httpManager.executeRequest(
            HttpRequest(
                for: clientPairChallengeResp,
                with: httpManager.newPairChallenge()
            )
        )

        Log.i("Pairing Stage #18")
        if !Self.verifyResponseStatus(clientPairChallengeResp) {
            return await finishPairing(bgId: bgId, forResponse: clientPairChallengeResp, withFallbackError: "Pairing stage #5 failed")
        }

        return finishPairing(bgId: bgId, withSuccess: derCertBytes)
    }
}

private extension PairManager {
    static func verifyResponseStatus(_ response: HttpResponse) -> Bool {
        guard response.isStatusOk,
              let pairedStatus = response.getIntTag("paired")
        else { return false }

        return pairedStatus == 1
    }

    static func concatData(_ data: Data, with moreData: Data) -> Data {
        var data = data
        data.append(moreData)
        return data
    }
}

extension PairManager {
    static func generatePin() -> String {
        let r = { Int.random(in: 0...9) }
        return "\(r())\(r())\(r())\(r())"
    }
}
