import AppKit
import GreekAccent

// Headless self-test of the composition logic (no event tap, no UI).
//   .build/release/ela --selftest
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

// Agent app: no Dock icon, lives only in the menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
