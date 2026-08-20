import AppKit

// Entry point. The app has no Dock icon and no windows — it lives entirely
// in the status bar (see AppDelegate).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
