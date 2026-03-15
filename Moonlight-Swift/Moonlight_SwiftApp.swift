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
    @State private var container: ModelContainer
    @State private var discoveryManager: DiscoveryManager
    @State private var settings: Settings

    init() {
        do {
            let container = try ModelContainer(for: TemporaryHost.self, Settings.self)
            let settings = Self.loadOrCreateSettings(in: container.mainContext)
            let discoveryManager = DiscoveryManager(
                modelContainer: container,
                isEnabled: !ProcessInfo.isRunningForXcodePreview
            )

            self.container = container
            self.discoveryManager = discoveryManager
            self.settings = settings
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HostsListView()
            }
            .environment(discoveryManager)
            .environment(settings)
        }
        .modelContainer(container)
    }
}

private extension Moonlight_SwiftApp {
    static func loadOrCreateSettings(in context: ModelContext) -> Settings {
        let descriptor = FetchDescriptor<Settings>()

        if let settings = try? context.fetch(descriptor).first {
            return settings
        }

        let settings = Settings()
        context.insert(settings)
        try? context.save()
        return settings
    }
}

private extension ProcessInfo {
    static var isRunningForXcodePreview: Bool {
        let environment = processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}
