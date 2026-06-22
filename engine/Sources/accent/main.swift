import Foundation
import GreekAccent

func findModelDir() -> String {
    let fm = FileManager.default
    for c in ["data/model", "../data/model", "./model"] where fm.fileExists(atPath: c + "/lexicon.tsv") {
        return c
    }
    return "data/model"
}

var args = Array(CommandLine.arguments.dropFirst())
var modelDir = findModelDir()
if let i = args.firstIndex(of: "--model"), i + 1 < args.count {
    modelDir = args[i+1]; args.removeSubrange(i...(i+1))
}

// collect --teach "<accented sentence>" (repeatable): apply user-learning first
var teachSentences: [String] = []
while let i = args.firstIndex(of: "--teach"), i + 1 < args.count {
    teachSentences.append(args[i+1]); args.removeSubrange(i...(i+1))
}

let t0 = Date()
let engine: Accentuer
do { engine = try Accentuer(modelDir: modelDir) }
catch { FileHandle.standardError.write("load failed (\(modelDir)): \(error)\n".data(using: .utf8)!); exit(1) }
let loadMs = Int(Date().timeIntervalSince(t0) * 1000)

for s in teachSentences { engine.learn(accentedTokens: Greek.tokenize(s)) }

func eprint(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// ---- eval mode --------------------------------------------------------------
if let i = args.firstIndex(of: "--eval"), i + 1 < args.count {
    let path = args[i+1]
    eprint("loaded \(engine.keyCount) keys, \(engine.homographCount) homographs in \(loadMs)ms")
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        eprint("cannot read \(path)"); exit(1)
    }
    var tok = 0, cov = 0
    var baseOK = 0, p1OK = 0, p2OK = 0
    var hTok = 0, hBase = 0, hP1 = 0, hP2 = 0
    var fixes = 0, regress = 0
    for line in text.split(separator: "\n") {
        let gold = Greek.tokenize(String(line))
        if gold.isEmpty { continue }
        let keys = gold.map { Greek.key($0) }
        let base = engine.accentBaseline(keys: keys)
        let p1 = engine.accent(keys: keys, useRight: false)
        let p2 = engine.accent(keys: keys, useRight: true)
        for j in gold.indices {
            tok += 1
            let isHomo = engine.isHomograph(keys[j])
            let inVocab = isHomo || base[j] != keys[j] || gold[j] == keys[j]
            if !inVocab { continue } // OOV (left as-typed, not in lexicon)
            cov += 1
            let g = gold[j]
            if base[j] == g { baseOK += 1 }
            if p1[j]  == g { p1OK  += 1 }
            if p2[j]  == g { p2OK  += 1 }
            if isHomo {
                hTok += 1
                if base[j] == g { hBase += 1 }
                if p1[j]  == g { hP1  += 1 }
                if p2[j]  == g { hP2  += 1 }
                if p1[j] != g && p2[j] == g { fixes += 1 }
                if p1[j] == g && p2[j] != g { regress += 1 }
            }
        }
    }
    func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "n/a" : String(format: "%.2f%%", 100.0 * Double(a) / Double(b)) }
    eprint("")
    eprint("tokens=\(tok)  in-vocab=\(cov)  coverage=\(pct(cov, tok))")
    eprint("ALL TOKENS      baseline=\(pct(baseOK,cov))  pass1(L)=\(pct(p1OK,cov))  pass2(L+R)=\(pct(p2OK,cov))")
    eprint("HOMOGRAPHS(\(hTok)) baseline=\(pct(hBase,hTok))  pass1(L)=\(pct(hP1,hTok))  pass2(L+R)=\(pct(hP2,hTok))")
    eprint("end-of-sentence: fixed=\(fixes)  regressed=\(regress)  (net \(fixes - regress))")
    exit(0)
}

// ---- weight sweep -----------------------------------------------------------
if let i = args.firstIndex(of: "--sweep"), i + 1 < args.count {
    let path = args[i+1]
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        eprint("cannot read \(path)"); exit(1)
    }
    // cache (keys, gold, isHomo) per sentence
    var data: [(keys: [String], gold: [String])] = []
    for line in text.split(separator: "\n") {
        let gold = Greek.tokenize(String(line))
        if gold.isEmpty { continue }
        data.append((gold.map { Greek.key($0) }, gold))
    }
    func homoAcc(useRight: Bool) -> Double {
        var ok = 0, n = 0
        for d in data {
            let out = engine.accent(keys: d.keys, useRight: useRight)
            for j in d.gold.indices where engine.isHomograph(d.keys[j]) {
                n += 1; if out[j] == d.gold[j] { ok += 1 }
            }
        }
        return n == 0 ? 0 : 100.0 * Double(ok) / Double(n)
    }
    var results: [(String, Double)] = []
    for wp in [0.5, 1.0] {
        for wl in [1.0, 2.0, 4.0, 6.0] {
            for wr in [1.0, 2.0, 4.0, 6.0] {
                for a in [0.05, 0.2, 0.5] {
                    var w = Weights(); w.prior = wp; w.left = wl; w.right = wr; w.alpha = a
                    engine.weights = w
                    let acc = homoAcc(useRight: true)
                    results.append(("p=\(wp) l=\(wl) r=\(wr) a=\(a)", acc))
                }
            }
        }
    }
    results.sort { $0.1 > $1.1 }
    eprint("top homograph pass2 accuracy:")
    for r in results.prefix(12) { eprint(String(format: "  %.3f%%  %@", r.1, r.0)) }
    exit(0)
}

// ---- trace mode: show live (pass1, word-by-word) vs sentence-end (pass2) ----
if let i = args.firstIndex(of: "--trace"), i + 1 < args.count {
    let toks = Greek.tokenize(args[i+1])
    let keys = toks.map { Greek.key($0) }
    // pass1: each word resolved with only its left neighbour (as while typing)
    var live: [String] = []
    for j in keys.indices {
        live.append(engine.accentOne(key: keys[j], prevKey: j > 0 ? keys[j-1] : nil, nextKey: nil))
    }
    let full = engine.accent(keys: keys, useRight: true)
    eprint("pass1 (live)      : " + live.joined(separator: " "))
    eprint("pass2 (sentence)  : " + full.joined(separator: " "))
    var flips: [String] = []
    for j in keys.indices where live[j] != full[j] { flips.append("\(keys[j]): \(live[j]) -> \(full[j])") }
    eprint("end-of-sentence flips: " + (flips.isEmpty ? "none" : flips.joined(separator: ", ")))
    exit(0)
}

// ---- interactive / pipe mode ------------------------------------------------
// Read lines from stdin (or accent the CLI args). Output accented (full pass2).
@MainActor
func accentLine(_ line: String) -> String {
    // Re-insert accents into Greek tokens while preserving everything else.
    let keys = Greek.tokenize(line).map { Greek.key($0) }
    let accented = engine.accent(keys: keys, useRight: true)
    var out = "", idx = 0
    let ns = line as NSString
    let re = try! NSRegularExpression(pattern: "\\p{Greek}+")
    var last = 0
    for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        out += idx < accented.count ? accented[idx] : ns.substring(with: m.range)
        last = m.range.location + m.range.length
        idx += 1
    }
    out += ns.substring(from: last)
    return out
}

if !args.isEmpty {
    print(accentLine(args.joined(separator: " ")))
    exit(0)
}

eprint("loaded \(engine.keyCount) keys, \(engine.homographCount) homographs in \(loadMs)ms — type Greek (no accents), Ctrl-D to quit")
while let line = readLine(strippingNewline: true) {
    print(accentLine(line))
}
