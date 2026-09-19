//
//  ExternalShortcutDetector.swift
//  Thor
//

import Cocoa
import Carbon.HIToolbox

enum ExternalShortcutDetector {
    static func controlShortcutOwners() -> [Int: String] {
        var owners = [Int: String]()
        merge(macOSControlShortcuts(), into: &owners)
        merge(magnetControlShortcuts(), into: &owners)
        merge(hiddenBarControlShortcuts(), into: &owners)
        return owners
    }

    private static func merge(_ incoming: [Int: String], into owners: inout [Int: String]) {
        owners.merge(incoming) { current, new in
            guard current != new else { return current }
            return "\(current), \(new)"
        }
    }

    private static func macOSControlShortcuts() -> [Int: String] {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let shortcuts = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return [:]
        }

        var owners = [Int: String]()
        for shortcutValue in shortcuts.values {
            guard let shortcut = shortcutValue as? [String: Any],
                  shortcut["enabled"] as? Bool == true,
                  let value = shortcut["value"] as? [String: Any],
                  value["type"] as? String == "standard",
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = integer(from: parameters[1]),
                  let modifierRawValue = integer(from: parameters[2]),
                  isControlOnlyCocoaModifiers(modifierRawValue) else {
                continue
            }
            owners[keyCode] = "macOS"
        }
        return owners
    }

    private static func magnetControlShortcuts() -> [Int: String] {
        let bundleIdentifier = "com.crowdcafe.windowmagnet"
        guard let preferences = UserDefaults(suiteName: bundleIdentifier) else {
            return [:]
        }

        var owners = [Int: String]()
        for preferenceKey in ["horizontalCommands", "verticalCommands"] {
            guard let data = preferences.data(forKey: preferenceKey),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            collectMagnetShortcuts(from: json, into: &owners)
        }
        return owners
    }

    private static func collectMagnetShortcuts(from value: Any, into owners: inout [Int: String]) {
        if let values = value as? [Any] {
            values.forEach { collectMagnetShortcuts(from: $0, into: &owners) }
            return
        }

        guard let dictionary = value as? [String: Any] else { return }
        if let keyboardShortcut = dictionary["keyboardShortcut"] as? [String: Any],
           keyboardShortcut["enabled"] as? Bool == true,
           let shortcut = keyboardShortcut["shortcut"] as? [String: Any],
           let keyCode = shortcut["carbonKeyCode"] as? Int,
           let modifiers = shortcut["carbonModifiers"] as? Int,
           modifiers == Int(controlKey) {
            owners[keyCode] = "Magnet"
        }

        dictionary.values.forEach { collectMagnetShortcuts(from: $0, into: &owners) }
    }

    private static func hiddenBarControlShortcuts() -> [Int: String] {
        guard let data = hiddenBarShortcutData(),
              let shortcut = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              shortcut["control"] as? Bool == true,
              shortcut["command"] as? Bool != true,
              shortcut["option"] as? Bool != true,
              shortcut["shift"] as? Bool != true,
              shortcut["function"] as? Bool != true,
              let keyCode = shortcut["keyCode"] as? Int else {
            return [:]
        }
        return [keyCode: "Hidden Bar"]
    }

    private static func hiddenBarShortcutData() -> Data? {
        let bundleIdentifier = "com.dwarvesv.minimalbar"
        if let data = UserDefaults(suiteName: bundleIdentifier)?.data(forKey: "globalKey") {
            return data
        }

        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Preferences")
            .appendingPathComponent("\(bundleIdentifier).plist")
        guard let preferences = NSDictionary(contentsOf: preferencesURL) as? [String: Any] else {
            return nil
        }
        return preferences["globalKey"] as? Data
    }

    private static func integer(from value: Any) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }

    private static func isControlOnlyCocoaModifiers(_ rawValue: Int) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(rawValue))
            .intersection(.deviceIndependentFlagsMask)
        return flags == .control
    }
}
