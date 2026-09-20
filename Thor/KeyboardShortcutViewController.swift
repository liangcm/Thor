//
//  KeyboardShortcutViewController.swift
//  Thor
//

import Cocoa
import Carbon.HIToolbox
import MASShortcut

private struct KeyboardKey: Hashable {
    let title: String
    let keyCode: Int
}

private protocol KeyboardKeyViewDelegate: AnyObject {
    func keyView(_ keyView: KeyboardKeyView, receivedAppAt url: URL)
    func keyViewDidRequestClear(_ keyView: KeyboardKeyView)
}

private final class KeyboardBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

}

private final class KeyboardKeyView: NSVisualEffectView, NSDraggingSource {
    static let internalAppType = NSPasteboard.PasteboardType("me.alvinzhu.Thor.keyboard-app")

    let keyboardKey: KeyboardKey
    weak var delegate: KeyboardKeyViewDelegate?
    private(set) var app: AppModel?

    private let iconView = NSImageView()
    private let keyLabel = NSTextField(labelWithString: "")
    private let conflictBadge = NSImageView()
    private var mouseDownEvent: NSEvent?
    private var isDropTarget = false
    private var conflictMessage: String?

    init(keyboardKey: KeyboardKey) {
        self.keyboardKey = keyboardKey
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.38
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -5)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        keyLabel.stringValue = keyboardKey.title.uppercased()
        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        keyLabel.textColor = .labelColor
        keyLabel.alignment = .center
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)

        conflictBadge.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                      accessibilityDescription: "Shortcut Conflict".localized())
        conflictBadge.contentTintColor = .systemRed
        conflictBadge.isHidden = true
        conflictBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(conflictBadge)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 64),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            keyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            keyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            keyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            conflictBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            conflictBadge.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            conflictBadge.widthAnchor.constraint(equalToConstant: 16),
            conflictBadge.heightAnchor.constraint(equalToConstant: 16)
        ])

        registerForDraggedTypes([.fileURL, Self.internalAppType])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(app: AppModel?, conflictMessage: String?) {
        self.app = app
        self.conflictMessage = conflictMessage
        iconView.image = app?.icon
        keyLabel.stringValue = app == nil ? keyboardKey.title.uppercased() :
            "⌃\(keyboardKey.title.uppercased())"
        keyLabel.font = app == nil ? .systemFont(ofSize: 22, weight: .medium) : .systemFont(ofSize: 12, weight: .bold)
        if conflictMessage != nil {
            keyLabel.textColor = NSColor(calibratedRed: 0.82, green: 0.25, blue: 0.27, alpha: 1)
        } else {
            keyLabel.textColor = app == nil ? NSColor.white.withAlphaComponent(0.92) :
                NSColor.white.withAlphaComponent(0.72)
        }
        toolTip = conflictMessage ?? app.map { "\($0.appDisplayName) · ⌃\(keyboardKey.title.uppercased())" }
        setAccessibilityLabel(conflictMessage ?? toolTip ?? keyboardKey.title)
        conflictBadge.isHidden = conflictMessage == nil
        updateAppearance()
    }

    private func updateAppearance() {
        let hasConflict = conflictMessage != nil
        layer?.backgroundColor = (isDropTarget ? NSColor.white.withAlphaComponent(0.22) :
            NSColor.black.withAlphaComponent(0.28)).cgColor
        layer?.borderColor = (hasConflict ? NSColor.systemRed.withAlphaComponent(0.72) :
            isDropTarget ? NSColor.white.withAlphaComponent(0.72) :
            NSColor.white.withAlphaComponent(0.2)).cgColor
        layer?.borderWidth = hasConflict || isDropTarget ? 1.4 : 1
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedAppURL(from: sender.draggingPasteboard) != nil else { return [] }
        isDropTarget = true
        updateAppearance()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        updateAppearance()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return draggedAppURL(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            isDropTarget = false
            updateAppearance()
        }

        guard let url = draggedAppURL(from: sender.draggingPasteboard) else { return false }
        delegate?.keyView(self, receivedAppAt: url)
        return true
    }

    private func draggedAppURL(from pasteboard: NSPasteboard) -> URL? {
        if let internalPath = pasteboard.string(forType: Self.internalAppType) {
            return URL(fileURLWithPath: internalPath)
        }

        guard let value = pasteboard.string(forType: .fileURL),
              let url = URL(string: value),
              url.pathExtension.lowercased() == "app" else {
            return nil
        }
        return url
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let app = app, let appURL = app.resolvedAppBundleURL, mouseDownEvent != nil else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(appURL.path, forType: Self.internalAppType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = app.icon ?? NSWorkspace.shared.icon(forFile: appURL.path)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard app != nil else { return nil }
        let menu = NSMenu()
        let clearItem = NSMenuItem(title: "Clear Shortcut".localized(),
                                   action: #selector(clearShortcut), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        return menu
    }

    @objc private func clearShortcut() {
        delegate?.keyViewDidRequestClear(self)
    }
}

final class KeyboardShortcutViewController: NSViewController, KeyboardKeyViewDelegate {
    private let rows: [[KeyboardKey]] = [
        [
            KeyboardKey(title: "1", keyCode: kVK_ANSI_1), KeyboardKey(title: "2", keyCode: kVK_ANSI_2),
            KeyboardKey(title: "3", keyCode: kVK_ANSI_3), KeyboardKey(title: "4", keyCode: kVK_ANSI_4),
            KeyboardKey(title: "5", keyCode: kVK_ANSI_5), KeyboardKey(title: "6", keyCode: kVK_ANSI_6),
            KeyboardKey(title: "7", keyCode: kVK_ANSI_7), KeyboardKey(title: "8", keyCode: kVK_ANSI_8),
            KeyboardKey(title: "9", keyCode: kVK_ANSI_9), KeyboardKey(title: "0", keyCode: kVK_ANSI_0),
            KeyboardKey(title: "-", keyCode: kVK_ANSI_Minus), KeyboardKey(title: "=", keyCode: kVK_ANSI_Equal)
        ],
        zip(Array("QWERTYUIOP"), [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T,
                                   kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P])
            .map { KeyboardKey(title: String($0.0), keyCode: $0.1) },
        zip(Array("ASDFGHJKL"), [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G,
                                  kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L])
            .map { KeyboardKey(title: String($0.0), keyCode: $0.1) },
        zip(Array("ZXCVBNM"), [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V,
                                kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M])
            .map { KeyboardKey(title: String($0.0), keyCode: $0.1) }
    ]

    private var keyViews = [KeyboardKey: KeyboardKeyView]()
    private let otherShortcutsLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusPill = NSVisualEffectView()

    override func loadView() {
        view = KeyboardBackgroundView(frame: NSRect(x: 0, y: 0, width: 960, height: 500))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = NSTextField(labelWithString: "Keyboard Mapping".localized())
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let helpLabel = NSTextField(wrappingLabelWithString: "Drag an app from Finder onto a key. The shortcut is Control plus that key.".localized())
        helpLabel.font = .systemFont(ofSize: 13)
        helpLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(helpLabel)

        let keyboardStack = NSStackView()
        keyboardStack.orientation = .vertical
        keyboardStack.alignment = .centerX
        keyboardStack.spacing = 10
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        for row in rows {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 10
            for key in row {
                let keyView = KeyboardKeyView(keyboardKey: key)
                keyView.delegate = self
                keyViews[key] = keyView
                rowStack.addArrangedSubview(keyView)
            }
            keyboardStack.addArrangedSubview(rowStack)
        }

        otherShortcutsLabel.font = .systemFont(ofSize: 11)
        otherShortcutsLabel.textColor = NSColor.white.withAlphaComponent(0.54)
        otherShortcutsLabel.alignment = .center
        otherShortcutsLabel.maximumNumberOfLines = 2
        otherShortcutsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(otherShortcutsLabel)

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.76)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        statusPill.material = .hudWindow
        statusPill.blendingMode = .withinWindow
        statusPill.state = .active
        statusPill.wantsLayer = true
        statusPill.layer?.cornerRadius = 13
        statusPill.layer?.cornerCurve = .continuous
        statusPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        statusPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        statusPill.layer?.borderWidth = 1
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.addSubview(statusLabel)
        view.addSubview(statusPill)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            helpLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            helpLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            helpLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            keyboardStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            keyboardStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            otherShortcutsLabel.topAnchor.constraint(equalTo: keyboardStack.bottomAnchor, constant: 12),
            otherShortcutsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            otherShortcutsLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
            otherShortcutsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            otherShortcutsLabel.bottomAnchor.constraint(lessThanOrEqualTo: statusPill.topAnchor, constant: -8),
            statusPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusPill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            statusPill.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            statusPill.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
            statusLabel.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -14),
            statusLabel.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 6),
            statusLabel.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -6)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reloadAssignments),
                                               name: .shortcutAssignmentsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadAssignments),
                                               name: .shortcutEnableStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadAssignments),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        reloadAssignments()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadAssignments()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadAssignments() {
        var conflictCount = 0
        let externallyConflictedKeys = detectExternalConflicts()

        for (key, keyView) in keyViews {
            let shortcut = makeShortcut(for: key)
            let matches = AppsManager.manager.selectedApps.filter { shortcutsEqual($0.shortcut, shortcut) }
            let conflict: String?
            if matches.count > 1 {
                conflict = String(format: "Thor has %d apps assigned to %@".localized(),
                                  matches.count, shortcutDisplayName(for: key))
            } else if let owner = externallyConflictedKeys[key.keyCode] {
                conflict = String(format: "%@ is occupied by %@".localized(),
                                  shortcutDisplayName(for: key), owner)
            } else {
                conflict = nil
            }
            keyView.configure(app: matches.first, conflictMessage: conflict)
            conflictCount += conflict == nil ? 0 : 1
        }

        var otherShortcuts = AppsManager.manager.selectedApps.compactMap { app -> String? in
            guard let shortcut = app.shortcut else { return nil }
            let appearsOnKeyboard = keyViews.keys.contains { shortcutsEqual(shortcut, makeShortcut(for: $0)) }
            guard !appearsOnKeyboard else { return nil }
            return "\(app.appDisplayName) \(shortcutDisplayName(shortcut))"
        }
        otherShortcuts.append("清除通知 ⌃−（仅通知中心展开时）")
        otherShortcuts.append("键盘背光 ⇧F1 / ⇧F2")
        otherShortcutsLabel.isHidden = otherShortcuts.isEmpty
        otherShortcutsLabel.stringValue = otherShortcuts.isEmpty ? "" :
            "Other global shortcuts".localized() + "：" + otherShortcuts.joined(separator: " · ")

        let globalState = defaults[.EnableShortcut] ? "Global shortcuts enabled".localized() :
            "Global shortcuts disabled".localized()
        let configuredCount = AppsManager.manager.selectedApps.filter { $0.shortcut != nil }.count
        if !externallyConflictedKeys.isEmpty {
            statusLabel.textColor = NSColor.white.withAlphaComponent(0.76)
            statusLabel.stringValue = globalState + " · " +
                String(format: "%d keys occupied externally · Red keys cannot be assigned".localized(),
                       externallyConflictedKeys.count)
        } else if conflictCount > 0 {
            statusLabel.textColor = NSColor.white.withAlphaComponent(0.76)
            statusLabel.stringValue = globalState + " · " +
                String(format: "%d shortcut conflicts found. Red keys need attention.".localized(), conflictCount)
        } else {
            statusLabel.textColor = NSColor.white.withAlphaComponent(0.76)
            statusLabel.stringValue = globalState + " · " +
                String(format: "%d shortcuts configured · Right-click a key to clear it".localized(), configuredCount)
        }
    }

    fileprivate func keyView(_ keyView: KeyboardKeyView, receivedAppAt url: URL) {
        guard let app = AppModel(appURL: url) else {
            presentAlert(title: "Unsupported Item".localized(),
                         message: "Only macOS application bundles (.app) can be dropped here.".localized())
            return
        }

        let shortcut = makeShortcut(for: keyView.keyboardKey)
        let occupant = AppsManager.manager.selectedApps.first {
            $0 != app && shortcutsEqual($0.shortcut, shortcut)
        }

        if let occupant = occupant {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Shortcut Already Assigned".localized()
            alert.informativeText = String(format: "%@ is currently assigned to %@. Replacing it will clear that app's shortcut.".localized(),
                                           shortcutDisplayName(for: keyView.keyboardKey), occupant.appDisplayName)
            alert.addButton(withTitle: "Replace".localized())
            alert.addButton(withTitle: "Cancel".localized())
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        if let externalOwner = knownExternalShortcutOwner(for: shortcut) {
            let thorState = occupant == nil ? "Not assigned inside Thor".localized() :
                String(format: "Currently assigned inside Thor to %@".localized(), occupant!.appDisplayName)
            presentAlert(title: "Shortcut Conflict".localized(),
                         message: String(format: "%@ cannot be registered.\n\nThor: %@\nExternal: %@\n\nChange the existing shortcut and try again.".localized(),
                                         shortcutDisplayName(for: keyView.keyboardKey), thorState,
                                         externalOwner))
            return
        }

        guard shortcutIsAvailableOutsideThor(shortcut) else {
            let thorState = occupant == nil ? "Not assigned inside Thor".localized() :
                String(format: "Currently assigned inside Thor to %@".localized(), occupant!.appDisplayName)
            presentAlert(title: "Shortcut Conflict".localized(),
                         message: String(format: "%@ cannot be registered.\n\nThor: %@\nmacOS or another app: already in use\n\nChange the existing shortcut and try again.".localized(),
                                         shortcutDisplayName(for: keyView.keyboardKey), thorState))
            return
        }

        AppsManager.manager.assign(app, shortcut: shortcut, replacing: occupant)
    }

    fileprivate func keyViewDidRequestClear(_ keyView: KeyboardKeyView) {
        guard let app = keyView.app else { return }
        AppsManager.manager.clearShortcut(for: app)
    }

    private func makeShortcut(for key: KeyboardKey) -> MASShortcut {
        return MASShortcut(keyCode: key.keyCode, modifierFlags: .control)
    }

    private func shortcutsEqual(_ lhs: MASShortcut?, _ rhs: MASShortcut) -> Bool {
        guard let lhs = lhs else { return false }
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask
        return lhs.keyCode == rhs.keyCode &&
            lhs.modifierFlags.intersection(mask) == rhs.modifierFlags.intersection(mask)
    }

    private func shortcutIsAvailableOutsideThor(_ shortcut: MASShortcut) -> Bool {
        ShortcutMonitor.unregister()
        guard let monitor = MASShortcutMonitor.shared() else {
            ShortcutMonitor.register()
            return false
        }
        let registered = monitor.register(shortcut, withAction: {})
        if registered {
            monitor.unregisterShortcut(shortcut)
        }
        ShortcutMonitor.register()
        return registered
    }

    private func knownExternalShortcutOwner(for shortcut: MASShortcut) -> String? {
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask
        guard shortcut.modifierFlags.intersection(mask) == NSEvent.ModifierFlags.control else { return nil }
        return ExternalShortcutDetector.controlShortcutOwners()[shortcut.keyCode]
    }

    private func detectExternalConflicts() -> [Int: String] {
        let shortcuts = keyViews.keys.map { ($0, makeShortcut(for: $0)) }
        guard !shortcuts.isEmpty else { return [:] }

        let visibleKeyCodes = Set(shortcuts.map { $0.0.keyCode })
        var conflicts = ExternalShortcutDetector.controlShortcutOwners().filter {
            visibleKeyCodes.contains($0.key)
        }

        ShortcutMonitor.unregister()
        guard let monitor = MASShortcutMonitor.shared() else {
            ShortcutMonitor.register()
            for (key, _) in shortcuts where conflicts[key.keyCode] == nil {
                conflicts[key.keyCode] = "macOS or another app".localized()
            }
            return conflicts
        }
        for (key, shortcut) in shortcuts {
            if monitor.register(shortcut, withAction: {}) {
                monitor.unregisterShortcut(shortcut)
            } else if conflicts[key.keyCode] == nil {
                conflicts[key.keyCode] = "macOS or another app".localized()
            }
        }
        ShortcutMonitor.register()
        return conflicts
    }

    private func shortcutDisplayName(for key: KeyboardKey) -> String {
        return "⌃\(key.title.uppercased())"
    }

    private func shortcutDisplayName(_ shortcut: MASShortcut) -> String {
        return shortcut.modifierFlagsString + shortcut.keyCodeString.uppercased()
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK".localized())
        alert.runModal()
    }
}
