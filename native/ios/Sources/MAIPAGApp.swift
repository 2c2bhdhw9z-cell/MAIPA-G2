import SwiftUI
import AgentCore

@main
struct MAIPAGApp: App {
    @StateObject private var appState = AppState()

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
}
