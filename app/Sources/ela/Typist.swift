import CoreGraphics

/// Synthesizes keyboard events to rewrite already-typed text.
/// All synthesized events are tagged so our own tap ignores them.
enum Typist {
    static let magic: Int64 = 0x454C41   // "ELA"
    private static let backspaceKey: CGKeyCode = 0x33

    static func isSynthetic(_ e: CGEvent) -> Bool {
        e.getIntegerValueField(.eventSourceUserData) == magic
    }

    private static func tag(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: magic)
        e.flags = []   // don't inherit physically-held modifiers (e.g. Shift from "?")
    }

    /// `count` backspace presses.
    static func backspace(_ src: CGEventSource?, count: Int) -> [CGEvent] {
        guard count > 0 else { return [] }
        var out = [CGEvent]()
        out.reserveCapacity(count * 2)
        for _ in 0..<count {
            if let d = CGEvent(keyboardEventSource: src, virtualKey: backspaceKey, keyDown: true)  { tag(d); out.append(d) }
            if let u = CGEvent(keyboardEventSource: src, virtualKey: backspaceKey, keyDown: false) { tag(u); out.append(u) }
        }
        return out
    }

    /// Insert a literal string via Unicode (layout-independent).
    static func insert(_ src: CGEventSource?, _ s: String) -> [CGEvent] {
        guard !s.isEmpty else { return [] }
        let u16 = Array(s.utf16)
        var out = [CGEvent]()
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
            u16.withUnsafeBufferPointer { buf in
                e.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: buf.baseAddress)
            }
            tag(e); out.append(e)
        }
        return out
    }

    /// Press a specific virtual key (used to re-emit Return/Enter).
    static func key(_ src: CGEventSource?, code: CGKeyCode) -> [CGEvent] {
        var out = [CGEvent]()
        if let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)  { tag(d); out.append(d) }
        if let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) { tag(u); out.append(u) }
        return out
    }

    static func post(_ events: [CGEvent]) {
        for e in events { e.post(tap: .cgSessionEventTap) }
    }
}
