import AppKit

// Entry point: run as a proper NSApplication (required for UI + event taps)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Hide from Dock — this is a menu bar app
app.setActivationPolicy(.accessory)

app.run()
