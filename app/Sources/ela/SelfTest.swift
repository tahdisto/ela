import Foundation
import GreekAccent

/// Headless verification of the composition logic with an in-memory sink.
@MainActor
enum SelfTest {
    private struct Case { let input: String; let expect: String }

    private static let cases: [Case] = [
        // basics + case preservation
        .init(input: "καλημερα ",                 expect: "καλημέρα "),
        .init(input: "Καλημερα ",                 expect: "Καλημέρα "),
        .init(input: "ΚΑΛΗΜΕΡΑ ",                 expect: "ΚΑΛΗΜΈΡΑ "),
        // homographs by context
        .init(input: "δεν θα το κανω ποτε.",       expect: "δεν θα το κάνω ποτέ."),
        .init(input: "θελω αλλα δυο.",             expect: "θέλω άλλα δύο."),
        .init(input: "ηρθαν ολοι αλλα εφυγαν.",     expect: "ήρθαν όλοι αλλά έφυγαν."),
        // end-of-sentence multi-word rewrite (the C case): ποτέ -> πότε at "."
        .init(input: "ποτε θα ερθεις.",            expect: "πότε θα έρθεις."),
        .init(input: "ποτε θα ερθεις\n",           expect: "πότε θα έρθεις\n"),
        // ? -> ; (Greek question mark)
        .init(input: "τι κανεις?",                 expect: "τι κάνεις;"),
        .init(input: "?",                          expect: ";"),
        // edges
        .init(input: "",                           expect: ""),
        .init(input: "  ",                         expect: "  "),
        .init(input: "123 ",                       expect: "123 "),
        .init(input: "ααα ",                       expect: "ααα "),     // OOV: unchanged
        .init(input: "καλημερα, ποσο κανει;",      expect: "καλημέρα, πόσο κάνει;"),
        // space before terminator: last token's separator is on screen
        .init(input: "ποτε θα ερθεις .",           expect: "πότε θα έρθεις ."),
        .init(input: "θελω αλλα δυο .",            expect: "θέλω άλλα δύο ."),
        // multiple sentences in a row (state resets per terminator)
        .init(input: "ποτε θα ερθεις. ποτε.",      expect: "πότε θα έρθεις. ποτέ."),
        // trailing space after a corrected word, no terminator
        .init(input: "ποτε ",                      expect: "ποτέ "),
        // punctuation clusters / no Greek
        .init(input: "...",                        expect: "..."),
        .init(input: "ok ",                        expect: "ok "),
    ]

    static func run() {
        guard let dir = Store.modelDir(), let engine = try? Accentuer(modelDir: dir) else {
            print("SELFTEST: model not found"); return
        }
        var pass = 0
        for c in cases {
            let sink = StringSink()
            let comp = Composer(engine: engine, sink: sink)
            comp.learning = false                  // deterministic
            comp.feed(c.input)
            let ok = sink.text == c.expect
            if ok { pass += 1 }
            let mark = ok ? "ok  " : "FAIL"
            print("\(mark)  in=\(vis(c.input))  got=\(vis(sink.text))" + (ok ? "" : "  exp=\(vis(c.expect))"))
        }
        print("---- \(pass)/\(cases.count) passed ----")
    }

    private static func vis(_ s: String) -> String {
        "«" + s.replacingOccurrences(of: "\n", with: "⏎") + "»"
    }
}
