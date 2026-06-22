import Carbon
import Foundation

/// Detects whether the current keyboard input source is Greek.
enum Layout {
    static func isGreek() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        guard let raw = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return false }
        let langs = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as NSArray
        for case let l as String in langs where l == "el" || l.hasPrefix("el-") { return true }
        return false
    }
}
