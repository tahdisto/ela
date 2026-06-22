import AppKit
import ApplicationServices
import GreekAccent

/// Wires the engine, the event tap and the composer together and owns the
/// enabled/permission state that the menu reflects.
@MainActor
final class Controller {
    private var engine: Accentuer?
    private var composer: Composer?
    private let tap = KeyTap()

    private(set) var modelOK = false
    // The three sub-options keep the user's remembered preference; the master
    // `enabled` gates them — when off they behave (and display) as off.
    var enabled = true { didSet { applyEffective(); onChange?() } }
    var sentenceRewrite = true { didSet { applyEffective(); onChange?() } }
    var learning = true { didSet { applyEffective(); onChange?() } }
    var greekQuestion = true { didSet { applyEffective(); onChange?() } }

    /// Effective (displayed/active) value of each sub-option.
    var effectiveSentenceRewrite: Bool { enabled && sentenceRewrite }
    var effectiveLearning: Bool       { enabled && learning }
    var effectiveGreekQuestion: Bool  { enabled && greekQuestion }

    private func applyEffective() {
        composer?.sentenceRewrite = effectiveSentenceRewrite
        composer?.learning        = effectiveLearning
        composer?.greekQuestion   = effectiveGreekQuestion
    }

    var onChange: (() -> Void)?

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isRunning: Bool { tap.isActive }

    func start() {
        guard let dir = Store.modelDir(), let engine = try? Accentuer(modelDir: dir) else {
            modelOK = false; onChange?(); return
        }
        modelOK = true
        if let data = Store.loadLearning() { engine.importLearning(data) }
        self.engine = engine

        let composer = Composer(engine: engine, sink: SystemSink())
        composer.onLearned = { [weak self] in self?.scheduleSave() }
        self.composer = composer
        applyEffective()

        tap.onEvent = { [weak self] type, event in
            self?.handle(type: type, event: event) ?? true
        }
        if accessibilityTrusted {
            _ = tap.start()
        } else {
            promptAccessibilityIfNeeded()   // one prompt; the watcher does the rest
        }
        startPermissionWatchIfNeeded()
        onChange?()
    }

    /// Poll until Accessibility is granted, then bring the tap up automatically —
    /// so toggling the switch in System Settings takes effect without a relaunch.
    private var permTimer: Timer?
    private func startPermissionWatchIfNeeded() {
        guard modelOK, !tap.isActive, permTimer == nil else { return }
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.tap.isActive, self.accessibilityTrusted {
                    _ = self.tap.start()
                    self.onChange?()
                }
                if self.tap.isActive {
                    self.permTimer?.invalidate()
                    self.permTimer = nil
                }
            }
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard enabled, Layout.isGreek() else { composer?.reset(); return true }
        switch type {
        case .keyDown:
            return composer?.keyDown(event) ?? true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            composer?.reset(); return true
        default:
            return true
        }
    }

    // MARK: permissions

    @discardableResult
    func promptAccessibilityIfNeeded() -> Bool {
        // literal avoids referencing the non-concurrency-safe global CFString
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Re-attempt to start the tap (after the user grants Accessibility).
    func retryTap() {
        guard modelOK, !tap.isActive else { return }
        if accessibilityTrusted { _ = tap.start() }
        startPermissionWatchIfNeeded()
        onChange?()
    }

    // MARK: learning persistence

    private var saveScheduled = false
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.saveScheduled = false
            self?.saveNow()
        }
    }

    func saveNow() {
        if let data = engine?.exportLearning() { Store.saveLearning(data) }
    }

    func clearLearning() {
        engine?.clearLearning()
        Store.clearLearning()
        onChange?()
    }
}
