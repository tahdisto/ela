import Foundation

/// In-memory model the user teaches by confirming accented sentences.
/// Blended additively into corpus scores (weighted by `userWeight`). Codable
/// so the app can persist it to disk.
final class UserModel: Codable {
    var prior: [String: [String: Double]] = [:]            // key -> form -> count
    var left:  [String: [String: [String: Double]]] = [:]  // key -> prevKey -> form -> count
    var right: [String: [String: [String: Double]]] = [:]  // key -> form -> nextKey -> count

    /// Per-(context, form) cap so repeating the same phrase can't snowball and
    /// override a clear corpus signal — learning nudges, it doesn't dominate.
    static let cap = 2.0

    private func add(_ v: inout Double, _ w: Double) { v = min(Self.cap, v + w) }

    func bump(key: String, form: String, prevKey: String, nextKey: String, by w: Double = 1) {
        add(&prior[key, default: [:]][form, default: 0], w)
        add(&left[key, default: [:]][prevKey, default: [:]][form, default: 0], w)
        add(&right[key, default: [:]][form, default: [:]][nextKey, default: 0], w)
    }

    func reset() { prior = [:]; left = [:]; right = [:] }
    func copy(from o: UserModel) { prior = o.prior; left = o.left; right = o.right }
}

/// Weights for the log-linear homograph scorer. Tuned on held-out data.
public struct Weights {
    public var prior: Double = 1.0
    public var left:  Double = 4.0
    public var right: Double = 4.0
    public var alpha: Double = 0.5      // additive smoothing
    public var userWeight: Double = 3.0 // weight of a (capped) user observation
    public init() {}
}

public final class Accentuer {
    private let lex: LexiconBin
    private let homo: HomographBin
    private let user = UserModel()
    public var weights = Weights()

    private static let BOS = "<s>", EOS = "</s>"

    public init(modelDir: String) throws {
        lex  = try LexiconBin(path: modelDir + "/lexicon.bin")
        homo = try HomographBin(path: modelDir + "/homographs.bin")
    }

    public var keyCount: Int { lex.count }
    public var homographCount: Int { homo.count }
    public func isHomograph(_ key: String) -> Bool { homo.contains(Array(key.utf8)) }

    // MARK: validity filtering (homograph candidates)

    /// Count accent marks (tonos/oxia/varia/perispomeni), excluding dialytika.
    static func tonosCount(_ s: String) -> Int {
        var n = 0
        for sc in s.decomposedStringWithCanonicalMapping.unicodeScalars
        where sc.properties.generalCategory == .nonspacingMark && sc != "\u{0308}" {
            n += 1
        }
        return n
    }

    /// Plausible forms for a homograph: <=1 tonos; polysyllables need exactly one.
    private func validCandidates(key: String, h: Homograph) -> [String] {
        let multi = Greek.syllableCount(key) >= 2
        let valid = h.formsByCount.filter { f in
            let t = Self.tonosCount(f)
            if t > 1 { return false }
            if multi && t == 0 { return false }
            return true
        }
        return valid.isEmpty ? h.formsByCount : valid
    }

    // MARK: scoring

    private func scoreForm(_ form: String, key: String, cands: [String], h: Homograph,
                           prevKey: String?, nextKey: String?) -> Double {
        let a = weights.alpha
        let F = Double(cands.count)
        let uw = weights.userWeight

        // prior
        let corpusPrior = Double(h.forms[form] ?? 0)
        let userPrior = (user.prior[key]?[form] ?? 0) * uw
        let totalPrior = cands.reduce(0.0) { acc, f in
            acc + Double(h.forms[f] ?? 0) + (user.prior[key]?[f] ?? 0) * uw
        }
        var score = log((corpusPrior + userPrior + a) / (totalPrior + a * F)) * weights.prior

        // left context: P(form | prevKey)
        if let pk = prevKey {
            let cMap = h.left[pk] ?? [:]
            let uMap = user.left[key]?[pk] ?? [:]
            let num = Double(cMap[form] ?? 0) + (uMap[form] ?? 0) * uw
            let den = cands.reduce(0.0) { acc, f in
                acc + Double(cMap[f] ?? 0) + (uMap[f] ?? 0) * uw
            }
            score += log((num + a) / (den + a * F)) * weights.left
        }

        // right context: P(form | nextKey)
        if let nk = nextKey {
            let num = Double(h.right[form]?[nk] ?? 0)
                    + (user.right[key]?[form]?[nk] ?? 0) * uw
            let den = cands.reduce(0.0) { acc, f in
                acc + Double(h.right[f]?[nk] ?? 0)
                    + (user.right[key]?[f]?[nk] ?? 0) * uw
            }
            score += log((num + a) / (den + a * F)) * weights.right
        }
        return score
    }

    private func resolveHomograph(key: String, h: Homograph,
                                  prevKey: String?, nextKey: String?) -> String {
        let cands = validCandidates(key: key, h: h)
        if cands.count == 1 { return cands[0] }
        var best = cands[0], bestScore = -Double.infinity
        for f in cands {
            let s = scoreForm(f, key: key, cands: cands, h: h, prevKey: prevKey, nextKey: nextKey)
            if s > bestScore { bestScore = s; best = f }
        }
        return best
    }

    // MARK: public API

    /// Accent a sequence of unaccented keys.
    /// `useRight`: include right context (false = live left-to-right pass1,
    /// true = end-of-sentence pass2 with full bidirectional context).
    public func accent(keys: [String], useRight: Bool) -> [String] {
        var out = [String](repeating: "", count: keys.count)
        for i in keys.indices {
            let key = keys[i]
            let bytes = Array(key.utf8)
            if let h = homo.lookup(bytes) {
                let pk = i > 0 ? keys[i-1] : Self.BOS
                let nk = useRight ? (i+1 < keys.count ? keys[i+1] : Self.EOS) : nil
                out[i] = resolveHomograph(key: key, h: h, prevKey: pk, nextKey: nk)
            } else {
                out[i] = lex.lookup(bytes) ?? key   // OOV: leave as typed
            }
        }
        return out
    }

    /// Resolve a single word given only its immediate neighbours. The scorer is
    /// bigram, so this is exactly equivalent to `accent` for one position but
    /// avoids re-resolving the whole left context on every keystroke.
    public func accentOne(key: String, prevKey: String?, nextKey: String?) -> String {
        let bytes = Array(key.utf8)
        guard let h = homo.lookup(bytes) else { return lex.lookup(bytes) ?? key }
        return resolveHomograph(key: key, h: h, prevKey: prevKey ?? Self.BOS, nextKey: nextKey)
    }

    /// Most-frequent-form baseline (no context) — for measuring context lift.
    public func accentBaseline(keys: [String]) -> [String] {
        keys.map { key in
            let bytes = Array(key.utf8)
            if let h = homo.lookup(bytes) { return validCandidates(key: key, h: h).first ?? key }
            return lex.lookup(bytes) ?? key
        }
    }

    /// Teach the model a confirmed accented sentence.
    public func learn(accentedTokens: [String]) {
        let keys = accentedTokens.map { Greek.key($0) }
        for i in accentedTokens.indices where homo.contains(Array(keys[i].utf8)) {
            let pk = i > 0 ? keys[i-1] : Self.BOS
            let nk = i+1 < keys.count ? keys[i+1] : Self.EOS
            user.bump(key: keys[i], form: accentedTokens[i], prevKey: pk, nextKey: nk)
        }
    }

    // MARK: learning persistence

    public func exportLearning() -> Data? { try? JSONEncoder().encode(user) }
    public func importLearning(_ data: Data) {
        if let u = try? JSONDecoder().decode(UserModel.self, from: data) { user.copy(from: u) }
    }
    public func clearLearning() { user.reset() }
}
