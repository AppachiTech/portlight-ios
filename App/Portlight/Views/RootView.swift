import PortlightSSH
import SwiftUI

/// Shows the lock screen until the device owner authenticates, covers the
/// app in the app switcher, and re-locks when the app leaves the foreground.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Set only by a real trip to the background. The Face ID sheet makes
    /// the scene briefly inactive, which must not count as leaving.
    @State private var wasInBackground = false

    var body: some View {
        ZStack {
            if model.lock.isUnlocked {
                MainView()
                    .transition(.opacity)
            } else {
                LockScreenView()
                    .transition(.opacity)
            }
            if scenePhase != .active {
                PrivacyCover()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.lock.isUnlocked)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasInBackground = true
                model.lock.didEnterBackground()
            case .active where wasInBackground:
                wasInBackground = false
                model.lock.willEnterForeground()
                if !model.lock.isUnlocked {
                    Task { await model.lock.unlock() }
                }
            default:
                break
            }
        }
        .task {
            if !model.lock.isUnlocked {
                await model.lock.unlock()
            }
        }
    }
}

/// What the app switcher sees: no terminal contents, no host names.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color.portlightNight.ignoresSafeArea()
            PortlightMark(size: 96)
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            HostListView()
                .tabItem { Label("Hosts", systemImage: "server.rack") }
            KeyListView()
                .tabItem { Label("Keys", systemImage: "key") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $model.showingTerminal) {
            TerminalScreen()
        }
    }
}
