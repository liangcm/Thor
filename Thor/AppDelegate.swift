//
//  AppDelegate.swift
//  Thor
//
//  Created by AlvinZhu on 4/18/16.
//  Copyright © 2016 AlvinZhu. All rights reserved.
//

import Cocoa
import MASShortcut
import LaunchAtLogin

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Properties

    var hasLaunched = false
    var isGoingToDisableShortcut = false

    var anewShortcutTimer: Timer?
    var delayTimer: Timer?

    var mainWindowController: MainWindowController?

    @IBOutlet weak var statusItemController: StatusItemController!

    // MARK: Life cycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Preserve preferences when moving from Thor's identity to Thor+.
        if let identifier = Bundle.main.bundleIdentifier,
           UserDefaults.standard.persistentDomain(forName: identifier) == nil,
           let legacy = UserDefaults.standard.persistentDomain(forName: "me.alvinzhu.Thor") {
            UserDefaults.standard.setPersistentDomain(legacy, forName: identifier)
        }
        defaults.register(defaults: [
            DefaultsKeys.DeactivateKey.key: 0,
            DefaultsKeys.DelayInterval.key: 0.3,
            DefaultsKeys.EnableShortcut.key: true,
            DefaultsKeys.enableMenuBarIcon.key: true,
            DefaultsKeys.enableMenuBarIconShowHideKey.key: true
            ])

        NSApp.setActivationPolicy(.accessory)

        if defaults[.enableMenuBarIcon] {
            sharedAppDelegate?.statusItemController.showInMenuBar()
        } else {
            sharedAppDelegate?.statusItemController.hideInMenuBar()
        }

        if defaults[.enableMenuBarIconShowHideKey] {
            registerMenubarIconShortcut()
        }

        shortcutEnableMonitor()

        if defaults.object(forKey: DefaultsKeys.LaunchAtLoginKey.key) != nil {
            defaults.removeObject(forKey: DefaultsKeys.LaunchAtLoginKey.key)
            LaunchAtLogin.isEnabled = defaults[.LaunchAtLoginKey]
        }

        MASShortcutValidator.shared().allowAnyShortcutWithOptionModifier = true
        ShortcutMonitor.register()
        NotificationClearShortcut.start()

        if AppsManager.manager.selectedApps.count == 0 {
            showMainWindow()
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        if hasLaunched {
            showMainWindow()
        } else {
            hasLaunched = true
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        let rootViewController = loadMainWindowController()
        rootViewController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleMainWindow() {
        if let window = mainWindowController?.window,
           window.isVisible, !window.isMiniaturized, !NSApp.isHidden {
            window.orderOut(nil)
        } else {
            mainWindowController?.window?.deminiaturize(nil)
            showMainWindow()
        }
    }

    private func loadMainWindowController() -> MainWindowController? {
        if let mainWindowController = mainWindowController {
            return mainWindowController
        }

        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let controller = storyboard.instantiateController(withIdentifier: MainWindowController.className)
            as? MainWindowController
        mainWindowController = controller
        _ = controller?.window
        return controller
    }

    // MARK: Listen events

    private func shortcutEnableMonitor() {
        let delayInterval: TimeInterval        = 0.3

        let shortcutActivateHandler = { (event: NSEvent) in
            let anewShortcutInterval: TimeInterval = defaults[.DelayInterval]
            let deactivateKey = MASShortcut.supportedModifiers[defaults[.DeactivateKey]]
            let modifier = event.modifierFlags.intersection(deactivateKey)

            if modifier == deactivateKey && defaults[.EnableDeactivateKey] {
                if self.isGoingToDisableShortcut {
                    self.isGoingToDisableShortcut = false

                    ShortcutMonitor.unregister()
                    defaults[.EnableShortcut] = false

                    self.anewShortcutTimer = Timer(timeInterval: anewShortcutInterval,
                                                   target: self,
                                                   selector: #selector(self.anewShortcutEnable),
                                                   userInfo: nil,
                                                   repeats: false)
                    RunLoop.current.add(self.anewShortcutTimer!, forMode: RunLoop.Mode.common)
                } else {
                    self.isGoingToDisableShortcut = true

                    self.delayTimer = Timer(timeInterval: delayInterval,
                                            target: self,
                                            selector: #selector(self.checkShortcutEnable(_:)),
                                            userInfo: nil,
                                            repeats: false)
                    RunLoop.current.add(self.delayTimer!, forMode: RunLoop.Mode.common)
                }
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: { (event) in
            shortcutActivateHandler(event)
        })

        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged], handler: { (event) -> NSEvent? in
            shortcutActivateHandler(event)
            return event
        })
    }

    @objc private func checkShortcutEnable(_ timer: Timer) {
        delayTimer?.invalidate()
        delayTimer = nil

        isGoingToDisableShortcut = false
    }

    @objc private func anewShortcutEnable(_ timer: Timer) {
        anewShortcutTimer?.invalidate()
        anewShortcutTimer = nil

        defaults[.EnableShortcut] = true
        ShortcutMonitor.register()
    }

    func registerMenubarIconShortcut() {
        let modifierFlags = NSEvent.ModifierFlags.shift.rawValue |
            NSEvent.ModifierFlags.control.rawValue |
            NSEvent.ModifierFlags.option.rawValue |
            NSEvent.ModifierFlags.command.rawValue
        let shortcut = MASShortcut(keyCode: kVK_ANSI_T, modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags))
        MASShortcutMonitor.shared().register(shortcut, withAction: {
            defaults[.enableMenuBarIcon] = !defaults[.enableMenuBarIcon]

            if defaults[.enableMenuBarIcon] {
                sharedAppDelegate?.statusItemController.showInMenuBar()
            } else {
                sharedAppDelegate?.statusItemController.hideInMenuBar()
            }

            NotificationCenter.default.post(name: .updateMenuBarToggleState, object: nil)
        })
    }

    func unregisterMenubarIconShortcut() {
        let modifierFlags = NSEvent.ModifierFlags.shift.rawValue |
            NSEvent.ModifierFlags.control.rawValue |
            NSEvent.ModifierFlags.option.rawValue |
            NSEvent.ModifierFlags.command.rawValue
        let shortcut = MASShortcut(keyCode: kVK_ANSI_T, modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags))
        MASShortcutMonitor.shared().unregisterShortcut(shortcut)
    }

}
