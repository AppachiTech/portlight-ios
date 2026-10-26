import PortlightSSH
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var library = model.library
        NavigationStack {
            Form {
                if let problem = model.startupProblem ?? model.library.lastError {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Terminal") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        LabeledContent("Theme", value: library.settings.themeName)
                    }
                    VStack(alignment: .leading) {
                        Text("Font size: \(Int(library.settings.fontSize)) pt")
                        Slider(value: $library.settings.fontSize, in: AppSettings.fontSizeRange, step: 1)
                    }
                    Picker("Cursor", selection: $library.settings.cursorStyle) {
                        Text("Block").tag(CursorStyle.block)
                        Text("Underline").tag(CursorStyle.underline)
                        Text("Bar").tag(CursorStyle.bar)
                    }
                    Toggle("Blinking cursor", isOn: $library.settings.cursorBlink)
                    Picker("Scrollback", selection: $library.settings.scrollbackLines) {
                        ForEach([1000, 5000, 10000, 50000], id: \.self) { lines in
                            Text("\(lines.formatted()) lines").tag(lines)
                        }
                    }
                    Toggle("Vibrate on bell", isOn: $library.settings.hapticBell)
                    Toggle("Keep screen awake in terminal", isOn: $library.settings.keepScreenAwake)
                    Picker("Orientation", selection: $library.settings.terminalOrientation) {
                        Text("Follow the phone").tag(TerminalOrientation.automatic)
                        Text("Landscape").tag(TerminalOrientation.landscape)
                        Text("Portrait").tag(TerminalOrientation.portrait)
                    }
                    NavigationLink("Saved commands") { SnippetsView() }
                }

                Section {
                    Toggle("Speak to type", isOn: $library.settings.voiceInput)
                } header: {
                    Text("Voice input")
                } footer: {
                    Text("A strip under the terminal takes speech, and the keyboard stays down until you ask for it. What you say lands in a draft, in lower case, that you can edit; Insert types it into the terminal without pressing Return. Speech is recognised on this iPhone and audio never leaves it.")
                }

                Section {
                    Picker("Lock", selection: lockGrace) {
                        ForEach(AppLockPolicy.allowedGracePeriods, id: \.self) { seconds in
                            Text(AppLockPolicy.describe(seconds)).tag(seconds)
                        }
                    }
                    Button {
                        model.lock.lockNow()
                    } label: {
                        Label("Lock now", systemImage: "lock")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Portlight always asks for Face ID, Touch ID or your passcode when it opens. Passwords and keys are kept in the Keychain on this device only and need that same check to be read.")
                }

                Section {
                    Picker("Keepalive", selection: $library.settings.keepAliveInterval) {
                        Text("Off").tag(0)
                        Text("Every 15 seconds").tag(15)
                        Text("Every 30 seconds").tag(30)
                        Text("Every 60 seconds").tag(60)
                    }
                    NavigationLink("Trusted host keys") { KnownHostsView() }
                    NavigationLink("Import ~/.ssh/config") { ImportConfigView() }
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Keepalive applies to new connections and helps them survive idle periods on mobile networks.")
                }

                Section {
                    NavigationLink("About Portlight") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var lockGrace: Binding<Int> {
        Binding(get: { model.library.settings.lockGracePeriod }, set: { seconds in
            model.library.settings.lockGracePeriod = seconds
            model.lock.setGracePeriod(seconds)
        })
    }
}

struct ThemePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(TerminalTheme.all) { theme in
            Button {
                model.library.settings.themeName = theme.name
            } label: {
                HStack(spacing: 12) {
                    ThemeSwatch(theme: theme)
                    Text(theme.name).foregroundStyle(.primary)
                    Spacer()
                    if model.library.settings.themeName == theme.name {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle("Theme")
    }
}

struct ThemeSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("$ ls -la")
                .font(.caption2.monospaced())
                .foregroundStyle(SwiftUI.Color(theme.foreground))
            HStack(spacing: 2) {
                ForEach(1..<7) { index in
                    Rectangle()
                        .fill(SwiftUI.Color(theme.ansi[index]))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(8)
        .frame(width: 92, alignment: .leading)
        .background(SwiftUI.Color(theme.background), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
