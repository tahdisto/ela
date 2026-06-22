import Foundation

/// Language the user can pick from the menu.
enum AppLang: String, CaseIterable { case en, el }

/// Tiny in-code localizer (English + Greek). No .strings files, no I/O —
/// switches instantly and adds nothing to the bundle.
enum L10n {
    enum Key {
        case statusActive, statusOff, statusNoPermission, statusNotRunning, statusNoModel
        case enabled, sentenceRewrite, learning, greekQuestion, clearLearning, openAccessibility
        case language, quit
    }

    private static let en: [Key: String] = [
        .statusActive:       "Active — Greek layout only",
        .statusOff:          "Off",
        .statusNoPermission: "Needs Accessibility permission",
        .statusNotRunning:   "Listener not running",
        .statusNoModel:      "Model not found",
        .enabled:            "Enabled",
        .sentenceRewrite:    "Correct accents at sentence end",
        .learning:           "Learn from Typing",
        .greekQuestion:      "Greek question mark (? → ;)",
        .clearLearning:      "Clear Learning Data",
        .openAccessibility:  "Open Accessibility Settings…",
        .language:           "Language",
        .quit:               "Quit",
    ]

    private static let el: [Key: String] = [
        .statusActive:       "Ενεργό — μόνο ελληνική διάταξη",
        .statusOff:          "Ανενεργό",
        .statusNoPermission: "Απαιτείται άδεια Προσβασιμότητας",
        .statusNotRunning:   "Η παρακολούθηση δεν εκτελείται",
        .statusNoModel:      "Το μοντέλο δεν βρέθηκε",
        .enabled:            "Ενεργοποιημένο",
        .sentenceRewrite:    "Διόρθωση τόνων στο τέλος της πρότασης",
        .learning:           "Μάθηση από την πληκτρολόγηση",
        .greekQuestion:      "Ελληνικό ερωτηματικό (? → ;)",
        .clearLearning:      "Εκκαθάριση δεδομένων μάθησης",
        .openAccessibility:  "Άνοιγμα ρυθμίσεων Προσβασιμότητας…",
        .language:           "Γλώσσα",
        .quit:               "Έξοδος",
    ]

    private static let key = "ela.language"

    static var selection: AppLang {
        get {
            if let raw = UserDefaults.standard.string(forKey: key), let l = AppLang(rawValue: raw) { return l }
            // first launch: default to the system locale, stored as a concrete value
            return (Locale.preferredLanguages.first?.hasPrefix("el") ?? false) ? .el : .en
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Resolved language code ("en" or "el").
    static var code: String { selection.rawValue }

    static func t(_ k: Key) -> String { (code == "el" ? el : en)[k] ?? en[k] ?? "" }
}
