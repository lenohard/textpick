import SwiftUI
import AppKit
import ServiceManagement

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    // Appearance
    @AppStorage("textpick.opacity")       private var opacity:     Double = 1.0
    @AppStorage("textpick.popupWidth")    private var popupWidth:  Double = 420
    @AppStorage("textpick.fontSize")      private var fontSize:    Double = 13
    @AppStorage("textpick.colorScheme")   private var colorScheme: String = "system"

    // Behaviour
    @AppStorage("textpick.autoCopy")           private var autoCopy:           Bool = false
    @AppStorage("textpick.showInputText")      private var showInputText:       Bool = true
    @AppStorage("textpick.closeOnEsc")         private var closeOnEsc:          Bool = true
    @AppStorage("textpick.switchToResult")     private var switchToResult:      Bool = true
    @AppStorage("textpick.captureMethod")      private var captureMethod:       String = "ax_first"
    @AppStorage("textpick.launchAtLogin")      private var launchAtLogin:      Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                // ── Hotkey ───────────────────────────────────────────
                sectionHeader("Global Hotkey", icon: "keyboard")
                    .padding(.bottom, 8)
                
                HotkeySettingsTab()
                    .frame(minHeight: 160)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .padding(.horizontal, 4)
                
                sectionDivider()
                    .padding(.top, 16)

                // ── Appearance ───────────────────────────────────────
                sectionHeader("Appearance", icon: "paintbrush")

                settingRow("Popup Opacity", note: "Affects the floating popup window.") {
                    HStack(spacing: 10) {
                        Slider(value: $opacity, in: 0.4...1.0, step: 0.05)
                            .frame(width: 160)
                        Text("\(Int(opacity * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                settingRow("Popup Width", note: nil) {
                    HStack(spacing: 10) {
                        Slider(value: $popupWidth, in: 320...700, step: 10)
                            .frame(width: 160)
                        Text("\(Int(popupWidth)) px")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                settingRow("Content Font Size", note: nil) {
                    HStack(spacing: 10) {
                        Slider(value: $fontSize, in: 10...18, step: 1)
                            .frame(width: 160)
                        Text("\(Int(fontSize)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                settingRow("Appearance", note: "Overrides system appearance for the popup.") {
                    Picker("", selection: $colorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .labelsHidden()
                    .onChange(of: colorScheme, perform: applyColorScheme)
                }

                sectionDivider()

                // ── Behaviour ────────────────────────────────────────
                sectionHeader("Behaviour", icon: "gearshape")

                settingRow("Auto-copy Result", note: "Copies LLM result to clipboard automatically.") {
                    Toggle("", isOn: $autoCopy).labelsHidden()
                }

                settingRow("Show Input Text", note: "Show the captured text above action buttons.") {
                    Toggle("", isOn: $showInputText).labelsHidden()
                }

                settingRow("Switch to Result View", note: "Automatically switch to result tab when processing starts.") {
                    Toggle("", isOn: $switchToResult).labelsHidden()
                }

                settingRow("Close on Escape", note: nil) {
                    Toggle("", isOn: $closeOnEsc).labelsHidden()
                }

                sectionDivider()

                // ── Text Capture ─────────────────────────────────────
                sectionHeader("Text Capture", icon: "text.cursor")

                settingRow("Capture Method", note: "AX = no clipboard disruption. Clipboard fallback copies via ⌘C.") {
                    Picker("", selection: $captureMethod) {
                        Text("Accessibility first").tag("ax_first")
                        Text("Clipboard only").tag("clipboard")
                        Text("Accessibility only").tag("ax_only")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .labelsHidden()
                }

                sectionDivider()

                // ── System ───────────────────────────────────────────
                sectionHeader("System", icon: "power")

                settingRow("Launch at Login", note: "Start TextPick automatically when you log in.") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { newValue in
                            toggleLaunchAtLogin(newValue)
                        }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
    }

    private func sectionDivider() -> some View {
        Divider().padding(.vertical, 4)
    }

    @ViewBuilder
    private func settingRow<Control: View>(
        _ label: String,
        note: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text(label)
                    .font(.system(size: 13))
                    .frame(width: 160, alignment: .leading)
                control()
                Spacer()
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 164)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }

    private func applyColorScheme(_ value: String) {
        guard let app = NSApp else { return }
        switch value {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark":  app.appearance = NSAppearance(named: .darkAqua)
        default:      app.appearance = nil
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently revert on failure (e.g. sandbox restrictions)
            launchAtLogin = !enabled
        }
    }
}
