@preconcurrency import CoreGraphics
import Foundation

/// Thin wrapper over a CGEventTap. Forwards events to `onEvent`, which returns
/// true to let the event pass or false to swallow it. Re-enables itself if the
/// system disables the tap (timeout / user input).
@MainActor
final class KeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onEvent: ((CGEventType, CGEvent) -> Bool)?

    var isActive: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            return MainActor.assumeIsolated { me.handle(type: type, event: event) }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        self.source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if Typist.isSynthetic(event) { return Unmanaged.passUnretained(event) }
        let pass = onEvent?(type, event) ?? true
        return pass ? Unmanaged.passUnretained(event) : nil
    }
}
