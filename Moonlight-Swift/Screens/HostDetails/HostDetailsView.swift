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
    }
}

struct AppView: View {
    let app: TemporaryApp

    @State private var image: UIImage?
    @State private var isStreaming: Bool = false
    @Namespace private var animation

    var body: some View {
        Button {
            isStreaming = true
        } label: {
            ZStack(alignment: .bottom) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ZStack {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Text(app.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .font(.footnote).bold()
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground).opacity(0.4))
            }
            .aspectRatio(.init(width: 3, height: 4), contentMode: .fill)
            .clipShape(.rect(cornerRadius: 25))
            .glassEffect(in: .rect(cornerRadius: 25))
        }
        .matchedTransitionSource(id: "zoom", in: animation)
        .task {
            guard let imageData = await ConnectionHelper.getHostAppAssets(app.id, for: app.host),
                  let image = UIImage(data: imageData, scale: 3)
            else {
                self.image = UIImage(systemName: "gamecontroller")
                return
            }

            self.image = image
        }
        .fullScreenCover(isPresented: $isStreaming) {
            NavigationStack {
                StreamingView(app: app)
            }
            .navigationTransition(.zoom(sourceID: "zoom", in: animation))
        }
    }
}
