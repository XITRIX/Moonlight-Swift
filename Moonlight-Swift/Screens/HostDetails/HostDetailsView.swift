//
//  HostDetailsView.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 11/03/2026.
//

import SwiftUI

struct HostDetailsView: View {
    var host: TemporaryHost
    @State private var apps: [TemporaryApp]?
    @State private var terminatingSession: Bool = false

    init(_ host: TemporaryHost) {
        self.host = host
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 12)]) {
                if let apps {
                    ForEach(apps) { app in
                        AppView(app: app)
                    }
                }
            }
            .padding()
        }
        .overlay {
            if apps == nil {
                ProgressView()
                    .controlSize(.extraLarge)
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            apps = await ConnectionHelper.getAppListForHost(host)
        }
        .toolbar {
            if host.currentlyInGame {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        terminatingSession = true
                    } label: {
                        Text("Terminate")
                            .foregroundStyle(.white)
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                    .confirmationDialog("Terminate current session?", isPresented: $terminatingSession, titleVisibility: .visible, actions: {
                        Button(role: .cancel) {}
                        Button("Terminare", role: .destructive) {

                        }
                    }) {
                        Text("All your unsaved progress could get lost")
                    }
                }
            }
        }
    }
}
