import Foundation

/// Greek text utilities. MUST match scripts/build_model.py exactly so that
/// keys produced here line up with keys baked into the model.
public enum Greek {

    /// Combining diaeresis (dialytika) — a vowel modifier, NOT an accent. Keep it.
    private static let dialytika: Unicode.Scalar = "\u{0308}"

    /// Strip tonos/oxia/varia/perispomeni; keep dialytika. Return NFC.
    public static func stripAccent(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for sc in s.decomposedStringWithCanonicalMapping.unicodeScalars {
            if sc.properties.generalCategory == .nonspacingMark && sc != dialytika {
                continue // drop accent mark
            }
            scalars.append(sc)
        }
        return String(scalars).precomposedStringWithCanonicalMapping
    }

    /// Lowercase + final-sigma normalization (trailing σ -> ς).
    public static func norm(_ tok: String) -> String {
        var t = tok.lowercased()
        if t.hasSuffix("σ") {
            t.removeLast()
            t.append("ς")
        }
        return t
    }

    /// Accent-stripped, normalized lookup key.
    public static func key(_ tok: String) -> String {
        stripAccent(norm(tok))
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: "\\p{Greek}+")

    /// Tokenize into normalized Greek word tokens (accents preserved).
    public static func tokenize(_ sentence: String) -> [String] {
        let ns = sentence as NSString
        let matches = tokenRegex.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
        return matches.map { norm(ns.substring(with: $0.range)) }
    }

    /// Number of vowel groups ~ syllables. Monosyllables normally take no tonos.
    public static func syllableCount(_ key: String) -> Int {
        let vowels = Set("αεηιουω")
        var count = 0
        var prevVowel = false
        for ch in key {
            let v = vowels.contains(ch)
            if v && !prevVowel { count += 1 }
            prevVowel = v
        }
        return count
    }
}
