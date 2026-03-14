//
//  Moonlight_SwiftApp.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import SwiftUI
import SwiftData

@main
struct Moonlight_SwiftApp: App {
    @State var container: ModelContainer
    @State var discoveryManager: DiscoveryManager

    init() {
        do {
            let container = try ModelContainer(for: TemporaryHost.self)
            let discoveryManager = DiscoveryManager(
                modelContainer: container,
                isEnabled: !ProcessInfo.isRunningForXcodePreview
            )

            self.container = container
            self.discoveryManager = discoveryManager
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DevicesListView()
            }
            .environment(discoveryManager)
        }
        .modelContainer(container)
    }
}

private extension ProcessInfo {
    static var isRunningForXcodePreview: Bool {
        let environment = processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}
