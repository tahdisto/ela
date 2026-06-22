import Foundation

/// Locates the bundled model and persists the user's learned data.
enum Store {
    /// Directory containing lexicon.bin / homographs.bin.
    static func modelDir() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath { candidates.append(res + "/model") }
        candidates += ["data/model", "../data/model",
                       "/Users/andrei/Documents/localGit/ela!/data/model"]
        return candidates.first { fm.fileExists(atPath: $0 + "/lexicon.bin") }
    }

    private static var learningURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ela", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("learning.json")
    }

    static func loadLearning() -> Data? { try? Data(contentsOf: learningURL) }
    static func saveLearning(_ data: Data) { try? data.write(to: learningURL, options: .atomic) }
    static func clearLearning() { try? FileManager.default.removeItem(at: learningURL) }
}
