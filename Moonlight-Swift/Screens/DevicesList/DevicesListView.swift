//
//  ContentView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import SwiftUI

//@Observable
//class DevicesListViewModel {
//    init() {
//        let manager = DiscoveryManager(hosts: [], andCallback: <#T##(any DiscoveryCallback)!#>)
//    }
//}

struct DevicesListView: View {
    @Environment(DiscoveryManager.self) var discoveryManager
//    @State private var viewModel: DevicesListViewModel = .init()

    var body: some View {
        let hosts = discoveryManager.hosts
        List {
            let groupedByPairing = Dictionary(grouping: hosts, by: \.pairState)
            ForEach([TemporaryHost.PairState.paired, .unpaired, .unknown]) { state in
                if let hosts = groupedByPairing[state]?.sorted(by: { $0.state.rawValue > $1.state.rawValue }),
                   !hosts.isEmpty
                {
                    Section {
                        ForEach(hosts) { host in
                            HostListView(host)
                        }
                    } header: {
                        Text(state.headerTitle)
                    }
                }
            }

            Section {} header: {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .animation(.default, value: hosts)
        .onAppear {
            discoveryManager.startDiscovery()
        }
        .onDisappear {
            discoveryManager.stopDiscovery()
        }
        .navigationTitle("Moonlight")
    }
}

private extension TemporaryHost.PairState {
    var headerTitle: String {
        switch self {
        case .unknown:
            ""
        case .unpaired:
            "Discovered"
        case .paired:
            "Paired"
        }
    }
}

extension Equatable {
    func presented(in array: [Self]) -> Bool {
        array.first(where: { $0 == self }) != nil
    }
}

#Preview {
    DevicesListView()
}
