import AppKit

// An agent app: no Dock icon and no application menu, only the status item and the panels.
// `LSUIElement` in the bundle's Info.plist does the same thing, but setting the policy here
// keeps a bare `swift run` behaving the same way as the packaged app.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// Top-level code is not main-actor isolated even though it runs on the main thread, and the
// delegate is @MainActor because everything it touches is AppKit.
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
