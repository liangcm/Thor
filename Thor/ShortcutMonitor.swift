//
//  ShortcutMonitor.swift
//  Thor
//
//  Created by Alvin on 5/14/16.
//  Copyright © 2016 AlvinZhu. All rights reserved.
//

import Foundation
import Cocoa
import MASShortcut
import ApplicationServices

struct ShortcutMonitor {

    static func register() {
        let apps = AppsManager.manager.selectedApps
        for app in apps where app.shortcut != nil {
            let registered = MASShortcutMonitor.shared().register(app.shortcut, withAction: {
                guard defaults[.EnableShortcut] else { return }

                if app.appBundleIdentifier == "thorplus.action.show-desktop" {
                    UserDefaults.standard.set("shortcut-triggered", forKey: "ShowDesktopLastStatus")
                    DesktopShortcut.toggle()
                    return
                }
                guard let appURL = app.resolvedAppBundleURL else { return }

                if app.appBundleIdentifier == Bundle.main.bundleIdentifier {
                    sharedAppDelegate?.toggleMainWindow()
                    return
                }

                if app.appBundleIdentifier == "com.apple.controlcenter" {
                    ControlCenterShortcut.show()
                    return
                }

                let targetAppIdentifier = app.appBundleIdentifier ?? Bundle(url: appURL)?.bundleIdentifier
                if let identifier = targetAppIdentifier,
                   let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == runningApp.processIdentifier,
                   WindowCycler.cycle(runningApp) {
                    return
                }
                if targetAppIdentifier == "com.apple.finder" {
                    // Finder keeps running after its last window is closed. Opening its app bundle again
                    // does not reliably create a window, so open the user's home folder explicitly.
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
                    return
                }

                if let frontmostAppIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    let targetAppIdentifier = targetAppIdentifier,
                    frontmostAppIdentifier == targetAppIdentifier {
                    NSRunningApplication.runningApplications(withBundleIdentifier: frontmostAppIdentifier).first?.hide()
                } else {
                    if #available(macOS 10.15, *) {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = true
                        NSWorkspace.shared.openApplication(at: appURL,
                                                           configuration: configuration) { _, error in
                            if let error = error {
                                NSLog("ERROR: \(error)")
                            }
                        }
                    } else {
                        NSWorkspace.shared.launchApplication(appURL.lastPathComponent)
                    }
                }
            })
            if app.appBundleIdentifier == "thorplus.action.show-desktop" {
                UserDefaults.standard.set(registered ? "registered" : "registration-conflict",
                                          forKey: "ShowDesktopRegistrationStatus")
            }
        }
    }

    static func unregister() {
        let apps = AppsManager.manager.selectedApps
        for app in apps where app.shortcut != nil {
            MASShortcutMonitor.shared().unregisterShortcut(app.shortcut)
        }
    }

}

// A conditional event tap leaves Control-minus untouched in every other app.
// Only notification alert accessibility actions are used; widgets are never cleared.
enum NotificationClearShortcut {
    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    private static var retryTimer: Timer?
    private static var clearing = false
    private static let worker = DispatchQueue(label: "com.liangcm.ThorPlus.notification-clear")
    private static let lock = NSLock()
    private static var panelWindowNumber: Int?
    private static var panelPID: pid_t?
    private static var panelTimer: DispatchSourceTimer?

    private static func diagnostic(_ state: String) {
        UserDefaults.standard.set(state, forKey: "NotificationClearLastStatus")
    }

    static func start() {
        installIfPermitted()
        if panelTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: worker)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler {
                let panel = expandedPanel()
                let number = panel.flatMap { attribute($0, "AXWindowNumber") as? Int }
                var pid: pid_t = 0
                if let panel = panel { AXUIElementGetPid(panel, &pid) }
                lock.lock()
                panelWindowNumber = number
                panelPID = panel == nil ? nil : pid
                lock.unlock()
            }
            panelTimer = timer
            timer.resume()
        }
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                installIfPermitted()
            }
        }
    }

    private static func installIfPermitted() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest:
                                (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << 14),
                               callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = NotificationClearShortcut.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if defaults[.EnableShortcut],
               let replacement = KeyboardBacklightShortcut.replacement(for: event, type: type) {
                return Unmanaged.passRetained(replacement)
            }
            let modifiers: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand]
            guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 27,
                  event.flags.intersection(modifiers) == .maskControl,
                  defaults[.EnableShortcut] else {
                return Unmanaged.passUnretained(event)
            }
            NotificationClearShortcut.diagnostic("key-received")
            guard NotificationClearShortcut.panelIsOnScreen() else {
                NotificationClearShortcut.diagnostic("panel-not-detected")
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !NotificationClearShortcut.clearing {
                NotificationClearShortcut.clearing = true
                NotificationClearShortcut.worker.async {
                    guard let panel = NotificationClearShortcut.expandedPanel() else {
                        DispatchQueue.main.async { NotificationClearShortcut.clearing = false }
                        NotificationClearShortcut.diagnostic("panel-closed-before-action")
                        return
                    }
                    NotificationClearShortcut.clearNext(in: panel, remaining: 100)
                }
            }
            return nil
        }, userInfo: nil)
        guard let tap = tap, let runSource = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            diagnostic("event-tap-unavailable")
            return
        }
        source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        diagnostic("event-tap-installed")
    }

    private static func panelIsOnScreen() -> Bool {
        lock.lock()
        let number = panelWindowNumber
        let pid = panelPID
        lock.unlock()
        guard let pid = pid,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? Int == Int(pid) else { return false }
            if let number = number { return window[kCGWindowNumber as String] as? Int == number }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Height"] ?? 0) > 400 && (bounds["Width"] ?? 0) > 250
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func descendants(_ root: AXUIElement, skipWidgets: Bool = false) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        let deadline = Date().addingTimeInterval(1)
        var index = 0
        while index < queue.count, index < 800, Date() < deadline {
            let element = queue[index]
            index += 1
            if skipWidgets,
               let identifier = attribute(element, kAXIdentifierAttribute) as? String,
               identifier.hasPrefix("widget-") { continue }
            result.append(element)
            queue.append(contentsOf: attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return result
    }

    private static func expandedPanel() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let process = NSRunningApplication.runningApplications(withBundleIdentifier:
                "com.apple.notificationcenterui").first else { return nil }
        let application = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        // A banner has the same window title, but never the widget editor control.
        return windows.first { window in
            descendants(window).contains {
                attribute($0, kAXIdentifierAttribute) as? String == "widget-editor-button"
            }
        }
    }

    private static func clearNext(in panel: AXUIElement, remaining: Int) {
        guard remaining > 0, defaults[.EnableShortcut], let current = expandedPanel(),
              CFEqual(current, panel) else {
            DispatchQueue.main.async { clearing = false }
            return
        }
        let clearLabels: Set<String> = ["Clear All", "Clear", "Close", "全部清除", "清除全部", "清除", "关闭"]
        var inspectedActions = 0
        var lastError: Int32 = 0
        for element in descendants(current, skipWidgets: true) {
            let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
            let isAlert = ["AXNotificationCenterAlert", "AXNotificationCenterAlertStack"].contains(subrole)
            var names: CFArray?
            guard AXUIElementCopyActionNames(element, &names) == .success,
                  let actions = names as? [String] else { continue }
            for action in actions {
                inspectedActions += 1
                var description: CFString?
                _ = AXUIElementCopyActionDescription(element, action as CFString, &description)
                // SwiftUI notification containers may have no alert subrole. Their custom
                // action names encode "Name:Close\nTarget:...", even when description is absent.
                let actionLabel = action.components(separatedBy: "\n").first ?? action
                let namedAction = actionLabel.hasPrefix("Name:") ? String(actionLabel.dropFirst(5)) : ""
                let descriptionMatches = isAlert && clearLabels.contains(description as String? ?? "")
                guard descriptionMatches || clearLabels.contains(namedAction) else { continue }
                let result = AXUIElementPerformAction(element, action as CFString)
                lastError = result.rawValue
                if result == .success {
                    diagnostic("notification-dismissed")
                    worker.asyncAfter(deadline: .now() + 0.12) {
                        clearNext(in: panel, remaining: remaining - 1)
                    }
                    return
                }
            }
        }
        diagnostic("no-dismiss-action; inspected=\(inspectedActions); error=\(lastError)")
        DispatchQueue.main.async { clearing = false }
    }
}

enum DesktopShortcut {
    private static let library = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)

    static func toggle() {
        guard let library = library, let symbol = dlsym(library, "CoreDockSendNotification") else {
            UserDefaults.standard.set("desktop-api-unavailable", forKey: "ShowDesktopLastStatus")
            NSSound.beep()
            return
        }
        // Same Dock notification used by Apple's Mission Control launcher.
        // Keep the library loaded for the lifetime of this function pointer.
        typealias SendNotification = @convention(c) (CFString, Int32) -> Void
        let send = unsafeBitCast(symbol, to: SendNotification.self)
        send("com.apple.showdesktop.awake" as CFString, 0)
        UserDefaults.standard.set("dock-toggle-sent", forKey: "ShowDesktopLastStatus")
    }
}

enum KeyboardBacklightShortcut {
    static func replacement(for event: CGEvent, type: CGEventType) -> CGEvent? {
        let mask: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand, .maskSecondaryFn]
        guard event.flags.intersection(mask) == .maskShift else { return nil }
        var data: Int
        if type.rawValue == 14, let original = NSEvent(cgEvent: event), original.subtype.rawValue == 8 {
            let key = (original.data1 >> 16) & 0xFFFF
            guard key == 2 || key == 3 else { return nil }
            // NX_KEYTYPE_BRIGHTNESS_UP/DOWN -> NX_KEYTYPE_ILLUMINATION_UP/DOWN.
            data = ((key == 2 ? 21 : 22) << 16) | (original.data1 & 0xFFFF)
        } else if type == .keyDown || type == .keyUp {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            guard key == 122 || key == 120 else { return nil }
            let state = type == .keyDown ? 0xA : 0xB
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? 1 : 0
            data = ((key == 120 ? 21 : 22) << 16) | (state << 8) | repeated
        } else { return nil }
        let replacement = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: 0, context: nil,
                                            subtype: 8, data1: data, data2: -1)?.cgEvent
        if replacement != nil {
            UserDefaults.standard.set("brightness-event-remapped", forKey: "KeyboardBacklightLastStatus")
        }
        return replacement
    }
}

enum AccessibilityPermission {
    private static var didPrompt = false

    static func check() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !didPrompt {
            didPrompt = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        return false
    }
}

enum ControlCenterShortcut {
    static func show() {
        guard AccessibilityPermission.check() else { return }
        // Use macOS's Fn-C command, not application activation (the process is always running).
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return }
        down.flags = .maskSecondaryFn
        keyUp.flags = .maskSecondaryFn
        down.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// Keep a stable order: AXWindows may reorder itself whenever a window is raised.
enum WindowCycler {
    private static var orderedWindows: [pid_t: [AXUIElement]] = [:]

    // True means handled (including unavailable permission/API); do not hide the app in that case.
    static func cycle(_ app: NSRunningApplication) -> Bool {
        guard AccessibilityPermission.check() else { return true }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let allWindows = value as? [AXUIElement] else { return true }
        let windows = allWindows.filter {
            var subrole: CFTypeRef?
            return AXUIElementCopyAttributeValue($0, kAXSubroleAttribute as CFString, &subrole) == .success &&
                (subrole as? String) == kAXStandardWindowSubrole
        }
        orderedWindows = orderedWindows.filter { NSRunningApplication(processIdentifier: $0.key) != nil }
        var ordered = (orderedWindows[app.processIdentifier] ?? []).filter { old in
            windows.contains { CFEqual(old, $0) }
        }
        for window in windows where !ordered.contains(where: { CFEqual($0, window) }) {
            ordered.append(window)
        }
        orderedWindows[app.processIdentifier] = ordered
        guard ordered.count > 1 else { return false }

        var focused: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused)
        let current = focused.flatMap { focused in ordered.firstIndex { CFEqual($0, focused) } }
        let next = ordered[current.map { ($0 + 1) % ordered.count } ?? 0]
        _ = AXUIElementSetAttributeValue(next, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let result = AXUIElementPerformAction(next, kAXRaiseAction as CFString)
        if result == .success {
            _ = AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            NSLog("Thor: unable to raise window (AX error %d)", result.rawValue)
        }
        return true
    }
}
