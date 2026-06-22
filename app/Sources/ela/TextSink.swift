import CoreGraphics

/// Where the composer writes its edits. The app uses the system (synthesized
/// keystrokes); tests use an in-memory string so the composition logic can be
/// verified without typing into real windows.
protocol TextSink: AnyObject {
    func backspace(_ n: Int)
    func insert(_ s: String)
    func pressReturn()
}

/// Real sink: rewrites the focused field via synthesized events.
final class SystemSink: TextSink {
    private let src = CGEventSource(stateID: .combinedSessionState)
    func backspace(_ n: Int) { Typist.post(Typist.backspace(src, count: n)) }
    func insert(_ s: String) { guard !s.isEmpty else { return }; Typist.post(Typist.insert(src, s)) }
    func pressReturn() { Typist.post(Typist.key(src, code: 0x24)) }
}

/// Test sink: applies edits to a plain string (graphemes), mirroring the screen.
final class StringSink: TextSink {
    private(set) var text = ""
    func backspace(_ n: Int) { for _ in 0..<min(n, text.count) { text.removeLast() } }
    func insert(_ s: String) { text += s }
    func pressReturn() { text += "\n" }
    func reset() { text = "" }
}
