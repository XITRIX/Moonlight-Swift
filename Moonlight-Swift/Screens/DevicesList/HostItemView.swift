//
//  HostItemView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 10.03.2026.
//

import SwiftUI

struct HostItemView: View {
    var host: TemporaryHost
    @Environment(DiscoveryManager.self) var discMan

    @State private var pairingPin: String? = nil
    @State private var showPairing: Bool = false

    init(_ host: TemporaryHost) {
        self.host = host
    }

    var body: some View {
        Group {
            if host.pairState == .paired, host.state == .online {
                NavigationLink {
                    HostDetailsView(host)
                } label: {
                    bodyLabel
                }

            } else {
                Button {
                    Task { await onClick() }
                } label: {
                    bodyLabel
                }
            }
        }
        .alert("Pairing", isPresented: $showPairing, presenting: pairingPin) { pin in
            Button("Cancel", role: .cancel) {
                pairingPin = nil
            }
        } message: { pin in
            Text("Input this PIN on your Host:\n\(pin)")
        }

    }
}

// MARK: Views
private extension HostItemView {
    @ViewBuilder
    var bodyLabel: some View {
        HStack {
            Text(host.name)
            Spacer()
            trailingView
        }
        .foregroundStyle(Color(.label))
    }

    @ViewBuilder
    var trailingView: some View {
        Group {
            switch host.state {
            case .offline:
                Image(systemName: "zzz")
            case .unknown:
                ProgressView()
            case .online:
                switch host.pairState {
                case .unknown:
                    ProgressView()
                case .unpaired:
                    Image(systemName: "lock.fill")
                case .paired:
                    EmptyView()
                }
            }
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(host.state == .offline ? Color.indigo : Color(.tertiaryLabel))
    }
}

// MARK: Actions
private extension HostItemView {
    func onClick() async {
        guard host.pairState == .unpaired,
            let hMan = HttpManager(host: host)
        else { return }

        let pin = PairManager.generatePin()
        pairingPin = pin
        showPairing = true
        defer {
            pairingPin = nil
            showPairing = false
        }

        let serverInfoResp = ServerInfoResponse()

        discMan.pauseDiscoveryForHost(host)
        await hMan.executeRequest(.init(for: serverInfoResp, with: hMan.newServerInfoRequest(fastFail: false), fallbackError: 401, fallbackRequest: hMan.newHttpServerInfoRequest()))
        discMan.resumeDiscoveryForHost(host)

        guard serverInfoResp.isStatusOk else {
            Log.w("Failed to get server info: \(serverInfoResp.statusMessage)")
            return
        }

        serverInfoResp.populateHost(host)
        if host.pairState == .paired {
            Log.i("Already paired")
            return
        }

        await discMan.stopDiscovery()
        defer { discMan.startDiscovery() }

        let pMan = PairManager(httpManager: hMan, clientCert: CryptoManager.readCertFromFile())

        let result = await pMan.startPairing(with: pin)

        Log.i("Pairing result: \(result)")

        switch result {
        case .pairSuccessful(let serverCert):
            host.serverCert = serverCert
        case .pairFailed(message: let message):
            break
        case .alreadyPaired:
            break
        }
        
//        host
//        try context.save()
    }
}
