// A stand-in for the deck, for watching what AppKit does to panels while displays come and go.
//
// Four borderless windows built the way PanelWindow builds them, put on one display, logging
// every screen-parameters notification, every window move with its time relative to the last
// screen change, and the screen list at each of those moments. Run it, unplug the display the
// windows are on, plug it back, and read the log.
//
//   swiftc -O -o probe-displays scripts/probe-displays.swift
//   ./probe-displays              # the last external display
//   ./probe-displays 9A2A4A31     # a display by the first characters of its UUID
//   ./probe-displays 2 --floating # by index, at the floating level so it is easy to see
//
// What it showed on 25 September 2026, and what the deck's parking is built on: the window
// server moves windows off a vanished display to the top edge of the nearest one, all to the
// same spot, and posts windowDidMove for each about 8 ms before didChangeScreenParameters, with
// NSScreen.screens already describing the new arrangement. On reconnect it puts back the windows
// it moved itself, again before the notification. The Dock follows the main display in a second
// notification 300 to 500 ms later, and the visible frames change again with it.
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let start = Date()
func stamp() -> String { String(format: "%8.3f", Date().timeIntervalSince(start)) }
func log(_ line: String) { print("[\(stamp())] \(line)") }
func rect(_ value: CGRect) -> String {
    String(format: "(%.0f,%.0f %.0fx%.0f)", value.minX, value.minY, value.width, value.height)
}
func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber
    return CGDirectDisplayID(number.uint32Value)
}
func uuid(of screen: NSScreen) -> String {
    guard let value = CGDisplayCreateUUIDFromDisplayID(displayID(of: screen)) else { return "display-\(displayID(of: screen))" }
    return String((CFUUIDCreateString(nil, value.takeRetainedValue()) as String).prefix(8))
}

var windows: [NSWindow] = []
var lastScreenChange: Date?

func dumpScreens(_ why: String) {
    log("screens [\(why)] main=\(NSScreen.main.map(uuid(of:)) ?? "nil")")
    for screen in NSScreen.screens {
        log("   \(uuid(of: screen)) \(screen.localizedName) frame=\(rect(screen.frame)) visible=\(rect(screen.visibleFrame))")
    }
}
func dumpWindows(_ why: String) {
    log("windows [\(why)]")
    for (index, window) in windows.enumerated() {
        let screen = window.screen.map(uuid(of:)) ?? "none"
        log("   w\(index) frame=\(rect(window.frame)) screen=\(screen) visible=\(window.isVisible)")
    }
}
func sample(_ why: String) {
    dumpScreens(why)
    dumpWindows(why)
}

let arguments = CommandLine.arguments.dropFirst()
let floating = arguments.contains("--floating")
let wanted = arguments.first { $0 != "--floating" }
let target = NSScreen.screens.first { screen in
    guard let wanted else { return false }
    return uuid(of: screen).hasPrefix(wanted) || String(NSScreen.screens.firstIndex(of: screen)!) == wanted
} ?? NSScreen.screens.last { CGDisplayIsBuiltin(displayID(of: $0)) == 0 } ?? NSScreen.main!

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
log("probe on \(uuid(of: target)) \(target.localizedName), level \(floating ? "floating" : "-1")")
dumpScreens("start")

let size = NSSize(width: 352, height: 200)
let offsets: [CGPoint] = [CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 300), CGPoint(x: 40, y: 560), CGPoint(x: 420, y: 40)]
let colours: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemOrange]
for (index, offset) in offsets.enumerated() {
    let origin = NSPoint(
        x: target.visibleFrame.minX + offset.x,
        y: target.visibleFrame.maxY - offset.y - size.height
    )
    let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = colours[index].withAlphaComponent(0.7)
    window.hasShadow = true
    window.level = floating ? .floating : NSWindow.Level(rawValue: -1)
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: "probe w\(index)  offset \(Int(offset.x)),\(Int(offset.y))")
    label.font = .boldSystemFont(ofSize: 18)
    label.textColor = .white
    label.frame = NSRect(x: 16, y: size.height - 44, width: size.width - 32, height: 28)
    window.contentView?.addSubview(label)
    window.orderFrontRegardless()
    windows.append(window)
}
dumpWindows("start")

let centre = NotificationCenter.default
centre.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { _ in
    lastScreenChange = Date()
    log(">>> didChangeScreenParameters")
    sample("at notification")
    for delay in [0.1, 0.3, 0.6, 1.0, 2.0, 4.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sample(String(format: "+%.1fs", delay)) }
    }
}
centre.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: nil) { note in
    guard let window = note.object as? NSWindow, let index = windows.firstIndex(of: window) else { return }
    let since = lastScreenChange.map { String(format: "%.3fs after screen change", Date().timeIntervalSince($0)) } ?? "no screen change yet"
    log("*** windowDidMove w\(index) -> \(rect(window.frame)) screen=\(window.screen.map(uuid(of:)) ?? "none") (\(since))")
    // What NSScreen says at this very moment: stale means a placement computed here is wrong.
    let seen = NSScreen.screens.map { "\(uuid(of: $0))=\(rect($0.visibleFrame))" }.joined(separator: " ")
    log("    NSScreen.screens now: \(seen)")
}
centre.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: nil) { note in
    guard let window = note.object as? NSWindow, let index = windows.firstIndex(of: window) else { return }
    log("*** windowDidChangeScreen w\(index) -> \(window.screen.map(uuid(of:)) ?? "none") frame=\(rect(window.frame))")
}
log("ready: unplug or mirror the display and plug it back; ctrl-c to stop")
app.run()
