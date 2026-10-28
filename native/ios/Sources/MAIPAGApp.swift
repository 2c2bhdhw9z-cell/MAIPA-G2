import SwiftUI
import BackgroundTasks
import AgentCore

@main
struct MAIPAGApp: App {
    @StateObject private var appState = AppState()

    init() {
        Self.registerBackgroundTasks()
    }

    private var preferredScheme: ColorScheme? {
        switch appState.settings.themeMode {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(state: appState)
                .preferredColorScheme(preferredScheme)
                .onOpenURL { url in
                    Task {
                        await appState.handleIncomingOAuthURL(url)
                    }
                }
        }
    }

    private static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "dev.maipag.app.refresh",
            using: nil
        ) { task in
            task.setTaskCompleted(success: true)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "dev.maipag.app.continued-processing",
            using: nil
        ) { task in
            task.setTaskCompleted(success: true)
        }
    }
}
