import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = Controller()

    private var statusLine: NSMenuItem!
    private var permItem: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var rewriteItem: NSMenuItem!
    private var learnItem: NSMenuItem!
    private var greekQItem: NSMenuItem!
    private var languageItem: NSMenuItem!
    private var clearItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var langItems: [(AppLang, NSMenuItem)] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        controller.onChange = { [weak self] in self?.refresh() }
        controller.start()
        refresh()
    }

    func applicationWillTerminate(_ note: Notification) { controller.saveNow() }

    // MARK: menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false   // we manage isEnabled ourselves

        statusLine = NSMenuItem(); statusLine.isEnabled = false
        menu.addItem(statusLine)

        permItem = item(#selector(openAccessibility))
        menu.addItem(permItem)

        menu.addItem(.separator())
        enabledItem = item(#selector(toggleEnabled));  menu.addItem(enabledItem)
        rewriteItem = item(#selector(toggleRewrite));  menu.addItem(rewriteItem)
        learnItem   = item(#selector(toggleLearning)); menu.addItem(learnItem)
        greekQItem  = item(#selector(toggleGreekQuestion)); menu.addItem(greekQItem)

        menu.addItem(.separator())
        languageItem = NSMenuItem()
        let sub = NSMenu()
        for lang in AppLang.allCases {
            let it = NSMenuItem(title: "", action: #selector(pickLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = lang.rawValue
            sub.addItem(it)
            langItems.append((lang, it))
        }
        languageItem.submenu = sub
        menu.addItem(languageItem)

        clearItem = item(#selector(clearLearning)); menu.addItem(clearItem)

        menu.addItem(.separator())
        quitItem = item(#selector(quit)); menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func item(_ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: "", action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    private func applyTitles() {
        permItem.title    = L10n.t(.openAccessibility)
        enabledItem.title = L10n.t(.enabled)
        rewriteItem.title = L10n.t(.sentenceRewrite)
        learnItem.title   = L10n.t(.learning)
        greekQItem.title  = L10n.t(.greekQuestion)
        languageItem.title = L10n.t(.language)
        clearItem.title   = L10n.t(.clearLearning)
        quitItem.title    = L10n.t(.quit)
        for (lang, it) in langItems {
            it.title = (lang == .el) ? "Ελληνικά" : "English"
            it.state = (lang == L10n.selection) ? .on : .off
        }
    }

    private func refresh() {
        applyTitles()

        let active = controller.enabled && controller.isRunning
        if let button = statusItem.button {
            // Template image → system gives it the same size, centring and
            // padding as the built-in menu-bar icons. ε inactive, έ active.
            button.image = Self.menuGlyph(active ? "έ" : "ε")
            button.imagePosition = .imageOnly
            button.title = ""
            button.alphaValue = active ? 1.0 : 0.55
        }

        enabledItem.state = controller.enabled ? .on : .off
        // when disabled: unchecked + greyed; remembered prefs return on re-enable
        rewriteItem.state = controller.effectiveSentenceRewrite ? .on : .off
        learnItem.state   = controller.effectiveLearning ? .on : .off
        greekQItem.state  = controller.effectiveGreekQuestion ? .on : .off
        rewriteItem.isEnabled = controller.enabled
        learnItem.isEnabled   = controller.enabled
        greekQItem.isEnabled  = controller.enabled

        let trusted = controller.accessibilityTrusted
        permItem.isHidden = trusted

        if !controller.modelOK            { statusLine.title = "⚠︎ " + L10n.t(.statusNoModel) }
        else if !trusted                  { statusLine.title = "⚠︎ " + L10n.t(.statusNoPermission) }
        else if !controller.isRunning     { statusLine.title = "⚠︎ " + L10n.t(.statusNotRunning) }
        else if !controller.enabled       { statusLine.title = L10n.t(.statusOff) }
        else                              { statusLine.title = L10n.t(.statusActive) }
    }

    // MARK: actions

    @objc private func toggleEnabled()  { controller.enabled.toggle() }
    @objc private func toggleRewrite()  { controller.sentenceRewrite.toggle() }
    @objc private func toggleLearning() { controller.learning.toggle() }
    @objc private func toggleGreekQuestion() { controller.greekQuestion.toggle() }
    @objc private func clearLearning()  { controller.clearLearning() }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = AppLang(rawValue: raw) {
            L10n.selection = lang
            refresh()
        }
    }

    @objc private func openAccessibility() {
        controller.promptAccessibilityIfNeeded()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller.retryTap() }
    }

    @objc private func quit() { controller.saveNow(); NSApp.terminate(nil) }

    /// Render the glyph as a monochrome template image so the menu bar treats it
    /// exactly like a system icon (size, vertical centring, tint, padding).
    private static func menuGlyph(_ s: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let ns = s as NSString
        let size = ns.size(withAttributes: attrs)
        let w = ceil(size.width) + 2, h = ceil(size.height)
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        ns.draw(at: NSPoint(x: (w - size.width) / 2, y: (h - size.height) / 2), withAttributes: attrs)
        img.unlockFocus()
        img.isTemplate = true   // system tints + aligns like other menu-bar icons
        return img
    }
}
