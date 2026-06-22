import CoreGraphics
import Foundation
import GreekAccent

/// Drives accent insertion from raw keystrokes.
///
/// - As a Greek word is typed it is buffered. On a word boundary (space, comma…)
///   the word is replaced with its accented form using LEFT context (pass 1).
/// - On a sentence terminator (. ; ! ? · Return) the whole sentence is
///   re-scored with FULL context (pass 2) and any earlier word whose accent
///   changed is rewritten in place. Then the sentence is learned.
///
/// All screen edits go through synthesized backspaces + Unicode inserts. We
/// keep an exact model of what we put on screen so multi-word rewrites are
/// deterministic. Any caret-moving event (mouse, arrows…) resets tracking, so
/// we never edit text we are no longer sure about.
@MainActor
final class Composer {
    private struct Tok { var key: String; var shown: String; var sep: String }

    private let engine: Accentuer
    private let sink: TextSink
    private var word = ""
    private var sentence: [Tok] = []

    /// User-facing toggle for the end-of-sentence multi-word rewrite (pass 2).
    var sentenceRewrite = true
    /// Reinforce the model with completed sentences.
    var learning = true
    /// Replace a typed "?" with the Greek question mark ";".
    var greekQuestion = true
    /// Called after a sentence is learned, so the controller can persist it.
    var onLearned: (() -> Void)?

    init(engine: Accentuer, sink: TextSink) { self.engine = engine; self.sink = sink }

    func reset() { word = ""; sentence = [] }

    // MARK: entry point

    /// Returns true to pass the event through, false to swallow it.
    func keyDown(_ e: CGEvent) -> Bool {
        let kc = e.getIntegerValueField(.keyboardEventKeycode)
        switch kc {
        case 0x33:                       // delete/backspace
            if !word.isEmpty { word.removeLast() } else { reset() }
            return true
        case 0x24, 0x4C:                 // return, keypad-enter -> terminator
            return finalizeSentence(boundary: .key(0x24))
        case 0x35, 0x30, 0x73, 0x77, 0x74, 0x79, 0x75,
             0x7B, 0x7C, 0x7D, 0x7E:     // esc, tab, home, end, pgup, pgdn, fwd-del, arrows
            reset(); return true
        default:
            break
        }

        let s = chars(of: e)
        if s.isEmpty { return true }
        return dispatch(char: s)
    }

    /// Route a single produced character. Shared by the live event path and
    /// `feed(_:)` (tests), so both behave identically.
    private func dispatch(char s: String) -> Bool {
        if isGreekLetter(s) { word += s; return true }
        // Greek question mark: a typed "?" becomes ";" (and ends the sentence)
        if s == "?" && greekQuestion {
            return finalizeSentence(boundary: .text(";"), rewriteBoundary: true)
        }
        return isTerminator(s) ? finalizeSentence(boundary: .text(s))
                               : finalizeWord(sep: s)
    }

    /// Drive the composer from a plain string (for tests / --selftest). "\n" is
    /// treated as Return. A character that passes through (not swallowed) is
    /// echoed into the sink, simulating what the OS types on screen — so a
    /// StringSink ends up holding exactly what the real screen would show.
    func feed(_ text: String) {
        for ch in text {
            let passed = (ch == "\n") ? finalizeSentence(boundary: .key(0x24))
                                      : dispatch(char: String(ch))
            if passed { sink.insert(String(ch)) }
        }
    }

    // MARK: word boundary (pass 1, left context only)

    private func finalizeWord(sep: String) -> Bool {
        guard !word.isEmpty else { return true }
        let key = Greek.key(word)
        let raw = engine.accentOne(key: key, prevKey: sentence.last?.key, nextKey: nil)
        let form = applyCase(of: word, to: raw)   // model forms are lowercase; keep the typed case
        defer { word = "" }

        if form != word {
            sink.backspace(word.count)
            sink.insert(form)
            sink.insert(sep)                      // re-emit the swallowed boundary
            sentence.append(Tok(key: key, shown: form, sep: sep))
            return false
        } else {
            sentence.append(Tok(key: key, shown: word, sep: sep))
            return true
        }
    }

    // MARK: sentence terminator (pass 2, full context, multi-word rewrite)

    private enum Boundary { case text(String); case key(CGKeyCode) }

    /// `rewriteBoundary`: emit the boundary ourselves even with no accent edits
    /// (used when the boundary char itself must change, e.g. ? → ;).
    private func finalizeSentence(boundary: Boundary, rewriteBoundary: Bool = false) -> Bool {
        if !word.isEmpty {
            sentence.append(Tok(key: Greek.key(word), shown: word, sep: ""))
            word = ""
        }
        guard !sentence.isEmpty else {
            // no tracked words, but the boundary itself may still need rewriting
            if rewriteBoundary, case .text(let s) = boundary {
                sink.insert(s); return false
            }
            return true
        }

        let keys = sentence.map { $0.key }
        // model forms are lowercase; restore each token's on-screen case so the
        // rewrite only fires on real accent changes, not case differences
        let raw = engine.accent(keys: keys, useRight: true)
        let forms = raw.indices.map { applyCase(of: sentence[$0].shown, to: raw[$0]) }
        let last = sentence.count - 1

        var didEdit = false
        if sentenceRewrite, let from = firstDiff(forms) {
            // delete the on-screen tail [from...last] and retype it corrected.
            // Each token's separator is already on screen too (including the
            // last one when a space precedes the terminator), so count it.
            var del = 0, retype = ""
            for j in from...last {
                del += sentence[j].shown.count + sentence[j].sep.count
                retype += forms[j] + sentence[j].sep
            }
            sink.backspace(del)
            sink.insert(retype)
            for j in from...last { sentence[j].shown = forms[j] }
            didEdit = true
        } else if !sentenceRewrite, forms[last] != sentence[last].shown {
            // rewrite disabled: still accent the final word with EOS context
            sink.backspace(sentence[last].shown.count + sentence[last].sep.count)
            sink.insert(forms[last] + sentence[last].sep)
            sentence[last].shown = forms[last]
            didEdit = true
        }

        let result: Bool
        if !didEdit && !rewriteBoundary {
            result = true                         // let the terminator pass through
        } else {
            switch boundary {
            case .text(let s): sink.insert(s)
            case .key:         sink.pressReturn()
            }
            result = false                        // we re-emitted the terminator
        }

        if learning {
            engine.learn(accentedTokens: sentence.map { $0.shown })
            onLearned?()
        }
        reset()
        return result
    }

    // MARK: helpers

    /// Re-apply `typed`'s per-character capitalization onto the (lowercase)
    /// accented `form`. They share the same letters, so indices line up.
    private func applyCase(of typed: String, to form: String) -> String {
        let t = Array(typed)
        guard t.contains(where: { $0.isUppercase }) else { return form }
        var out = ""
        for (i, ch) in form.enumerated() {
            out += (i < t.count && t[i].isUppercase) ? String(ch).uppercased() : String(ch)
        }
        return out
    }

    private func firstDiff(_ forms: [String]) -> Int? {
        for i in sentence.indices where forms[i] != sentence[i].shown { return i }
        return nil
    }

    private func chars(of e: CGEvent) -> String {
        var len = 0
        var buf = [UniChar](repeating: 0, count: 8)
        e.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &buf)
        return len > 0 ? String(utf16CodeUnits: buf, count: len) : ""
    }

    private func isGreekLetter(_ s: String) -> Bool {
        for sc in s.unicodeScalars {
            let v = sc.value
            let greek = (0x370...0x3FF).contains(v) || (0x1F00...0x1FFF).contains(v)
            let combiner = v == 0x300 || v == 0x301 || v == 0x308 || v == 0x342
            if !(greek || combiner) { return false }
        }
        return true
    }

    private func isTerminator(_ s: String) -> Bool {
        s == "." || s == "!" || s == "?" || s == ";" || s == "·" || s == "…"
    }
}
