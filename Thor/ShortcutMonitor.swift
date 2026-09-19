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

struct ShortcutMonitor {

    static func register() {
        let apps = AppsManager.manager.selectedApps
        for app in apps where app.shortcut != nil {
            MASShortcutMonitor.shared().register(app.shortcut, withAction: {
                guard let appURL = app.resolvedAppBundleURL else { return }
                guard defaults[.EnableShortcut] else { return }

                let targetAppIdentifier = app.appBundleIdentifier ?? Bundle(url: appURL)?.bundleIdentifier
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
        }
    }

    static func unregister() {
        let apps = AppsManager.manager.selectedApps
        for app in apps where app.shortcut != nil {
            MASShortcutMonitor.shared().unregisterShortcut(app.shortcut)
        }
    }

}
