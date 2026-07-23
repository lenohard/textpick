import SwiftUI
import AppKit
import ServiceManagement

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @AppStorage("textpick.opacity")       private var opacity:     Double = 1.0
    @AppStorage("textpick.popupWidth")    private var popupWidth:  Double = 420
    @AppStorage("textpick.fontSize")      private var fontSize:    Double = 13
    @AppStorage("textpick.colorScheme")   private var colorScheme: String = "system"

    @AppStorage("textpick.autoCopy")            private var autoCopy: Bool = false
    @AppStorage("textpick.showInputText")       private var showInputText: Bool = true
    @AppStorage("textpick.closeOnEsc")          private var closeOnEsc: Bool = true
    @AppStorage("textpick.switchToResult")      private var switchToResult: Bool = true
    @AppStorage("textpick.captureMethod")       private var captureMethod: String = "ax_first"
    @AppStorage("textpick.autoShowOnSelection") private var autoShowOnSelection: Bool = false
    @AppStorage("textpick.selectionTriggerStyle") private var selectionTriggerStyle: String = "compact"
    @AppStorage("textpick.launchAtLogin")       private var launchAtLogin: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard("Global Hotkey", icon: "keyboard") {
                    HotkeySettingsTab()
                }

                settingsCard("Appearance", icon: "paintbrush") {
                    settingRow("Popup Opacity", note: "Controls the floating result window.") {
                        HStack(spacing: 10) {
                            Slider(value: $opacity, in: 0.4...1.0, step: 0.05)
                                .frame(width: 170)
                            valueLabel("\(Int(opacity * 100))%", width: 42)
                        }
                    }
                    rowDivider()
                    settingRow("Popup Width", note: "Adjust the default popup width.") {
                        HStack(spacing: 10) {
                            Slider(value: $popupWidth, in: 320...700, step: 10)
                                .frame(width: 170)
                            valueLabel("\(Int(popupWidth)) px", width: 58)
                        }
                    }
                    rowDivider()
                    settingRow("Content Font Size", note: "Changes text in the popup content area.") {
                        HStack(spacing: 10) {
                            Slider(value: $fontSize, in: 10...18, step: 1)
                                .frame(width: 170)
                            valueLabel("\(Int(fontSize)) pt", width: 42)
                        }
                    }
                    rowDivider()
                    settingRow("Color Scheme", note: "Overrides the system appearance for the popup.") {
                        Picker("", selection: $colorScheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        .labelsHidden()
                        .onChange(of: colorScheme, perform: applyColorScheme)
                    }
                }

                settingsCard("Behaviour", icon: "gearshape") {
                    settingRow("Auto-copy Result", note: "Copy the generated result to the clipboard.") {
                        compactToggle($autoCopy)
                    }
                    rowDivider()
                    settingRow("Show Input Text", note: "Show captured text above the action buttons.") {
                        compactToggle($showInputText)
                    }
                    rowDivider()
                    settingRow("Switch to Result", note: "Open the result view as soon as processing starts.") {
                        compactToggle($switchToResult)
                    }
                    rowDivider()
                    settingRow("Close on Escape", note: "Dismiss the popup with the Escape key.") {
                        compactToggle($closeOnEsc)
                    }
                    rowDivider()
                    settingRow("Auto-show on Selection", note: "Show TextPick whenever text is selected.") {
                        compactToggle($autoShowOnSelection)
                    }
                    if autoShowOnSelection {
                        rowDivider()
                        settingRow("Selection Style", note: "Choose a compact bar or the complete popup.") {
                            Picker("", selection: $selectionTriggerStyle) {
                                Text("Compact Bar").tag("compact")
                                Text("Full Popup").tag("popup")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 230)
                            .labelsHidden()
                        }
                    }
                }

                settingsCard("Capture & System", icon: "text.cursor") {
                    settingRow("Capture Method", note: "Accessibility avoids changing the clipboard.") {
                        Picker("", selection: $captureMethod) {
                            Text("Accessibility first").tag("ax_first")
                            Text("Clipboard only").tag("clipboard")
                            Text("Accessibility only").tag("ax_only")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                        .labelsHidden()
                    }
                    rowDivider()
                    settingRow("Launch at Login", note: "Start TextPick automatically after login.") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { newValue in
                                toggleLaunchAtLogin(newValue)
                            }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func settingRow<Control: View>(
        _ label: String,
        note: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 6)
    }

    private func rowDivider() -> some View {
        Divider().opacity(0.55)
    }

    private func valueLabel(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    private func compactToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func applyColorScheme(_ value: String) {
        guard let app = NSApp else { return }
        switch value {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
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
