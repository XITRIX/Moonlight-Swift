//
//  ContentView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import SwiftUI
import SwiftData

struct HostsListView: View {
    @Environment(DiscoveryManager.self) var discoveryManager

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
                            HostItemView(host)
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
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {

                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
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
    NavigationStack {
        HostsListView()
    }
    .environment(DiscoveryManager(modelContainer: try! ModelContainer(for: TemporaryHost.self), isEnabled: false))
}
