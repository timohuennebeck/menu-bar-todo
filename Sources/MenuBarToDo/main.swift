import AppKit

// Entry point. The app has no Dock icon and no windows — it lives entirely
// in the status bar (see AppDelegate).
let app = NSApplication.shared
// Top-level code isn't main-actor isolated in Swift 5 mode; the delegate is.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
