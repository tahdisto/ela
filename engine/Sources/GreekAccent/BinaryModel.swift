import Foundation

/// One ambiguous key's data, parsed on demand from homographs.bin.
struct Homograph {
    let forms: [String: Int]                 // form -> corpus count
    let left:  [String: [String: Int]]       // prevKey -> form -> count
    let right: [String: [String: Int]]       // form -> nextKey -> count
    let formsByCount: [String]               // forms, most frequent first
}

@inline(__always) private func ru16(_ p: UnsafePointer<UInt8>, _ o: Int) -> Int {
    Int(p[o]) | (Int(p[o+1]) << 8)
}
@inline(__always) private func ru32(_ p: UnsafePointer<UInt8>, _ o: Int) -> Int {
    Int(p[o]) | (Int(p[o+1]) << 8) | (Int(p[o+2]) << 16) | (Int(p[o+3]) << 24)
}
@inline(__always) private func cmpKey(_ p: UnsafePointer<UInt8>, _ len: Int, _ key: [UInt8]) -> Int {
    let n = min(len, key.count)
    var i = 0
    while i < n { let d = Int(p[i]) - Int(key[i]); if d != 0 { return d }; i += 1 }
    return len - key.count
}

/// Memory-mapped, binary-searched store. Keys are sorted by raw UTF-8 bytes.
/// Header: magic[4], u32 count, u32 offset[count], then records.
final class MappedStore {
    let data: Data
    let count: Int
    let offTable = 8
    let recBase: Int

    init(path: String, magic: [UInt8]) throws {
        data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        count = data.withUnsafeBytes { raw -> Int in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<4 where p[i] != magic[i] { fatalError("bad model magic in \(path)") }
            return ru32(p, 4)
        }
        recBase = 8 + count * 4
    }

    /// Binary search; on hit returns the record's start offset, else nil.
    @inline(__always)
    func recordOffset(_ p: UnsafePointer<UInt8>, _ key: [UInt8]) -> Int? {
        var lo = 0, hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let rec = recBase + ru32(p, offTable + mid * 4)
            let cmp = cmpKey(p + rec + 2, ru16(p, rec), key)
            if cmp == 0 { return rec }
            else if cmp < 0 { lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return nil
    }
}

/// lexicon.bin: key -> best accented form. (~95% fast path)
final class LexiconBin {
    private let store: MappedStore
    init(path: String) throws { store = try MappedStore(path: path, magic: Array("ELX1".utf8)) }
    var count: Int { store.count }

    func lookup(_ key: [UInt8]) -> String? {
        store.data.withUnsafeBytes { raw -> String? in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            guard let rec = store.recordOffset(p, key) else { return nil }
            let klen = ru16(p, rec)
            let fp = rec + 2 + klen
            let flen = ru16(p, fp)
            return String(decoding: UnsafeBufferPointer(start: p + fp + 2, count: flen), as: UTF8.self)
        }
    }
}

/// homographs.bin: only ambiguous keys, with context tables. Parsed on demand.
final class HomographBin {
    private let store: MappedStore
    init(path: String) throws { store = try MappedStore(path: path, magic: Array("EHM1".utf8)) }
    var count: Int { store.count }

    func contains(_ key: [UInt8]) -> Bool {
        store.data.withUnsafeBytes { raw -> Bool in
            store.recordOffset(raw.bindMemory(to: UInt8.self).baseAddress!, key) != nil
        }
    }

    func lookup(_ key: [UInt8]) -> Homograph? {
        store.data.withUnsafeBytes { raw -> Homograph? in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            guard let rec = store.recordOffset(p, key) else { return nil }
            var cur = rec
            func str() -> String {
                let len = ru16(p, cur); cur += 2
                let s = String(decoding: UnsafeBufferPointer(start: p + cur, count: len), as: UTF8.self)
                cur += len; return s
            }
            func u16() -> Int { let v = ru16(p, cur); cur += 2; return v }
            func u32() -> Int { let v = ru32(p, cur); cur += 4; return v }

            _ = str()                        // key (skip)
            let nForms = u16()
            var formList = [String](); formList.reserveCapacity(nForms)
            var forms = [String: Int](minimumCapacity: nForms)
            for _ in 0..<nForms {
                let f = str(); let c = u32()
                formList.append(f); forms[f] = c
            }
            var left = [String: [String: Int]]()
            let nLeft = u32()
            for _ in 0..<nLeft {
                let pk = str(); let m = u32()
                var fc = [String: Int](minimumCapacity: m)
                for _ in 0..<m { let fi = u16(); let c = u32(); fc[formList[fi]] = c }
                left[pk] = fc
            }
            var right = [String: [String: Int]]()
            let nRight = u32()
            for _ in 0..<nRight {
                let fi = u16(); let nk = str(); let c = u32()
                right[formList[fi], default: [:]][nk] = c
            }
            return Homograph(forms: forms, left: left, right: right, formsByCount: formList)
        }
    }
}
