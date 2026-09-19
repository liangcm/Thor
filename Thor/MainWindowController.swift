//
//  MainWindowController.swift
//  Thor
//
//  Created by AlvinZhu on 4/20/16.
//  Copyright © 2016 AlvinZhu. All rights reserved.
//

import Cocoa

class MainWindowController: TOLWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()

        window?.contentView?.layer?.masksToBounds = true

        let keyboardItem = TitleViewItem(itemIdentifier: keyboardTitleItemIdentifier.rawValue)
        let keyboardImage = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Mapping".localized())
        keyboardItem.activeImage = keyboardImage
        keyboardItem.inactiveImage = keyboardImage

        let appItem = TitleViewItem(itemIdentifier: appsTitleItemIdentifier.rawValue)
        let appImage = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Apps".localized())
        appItem.activeImage = appImage
        appItem.inactiveImage = appImage

        let settingsItem = TitleViewItem(itemIdentifier: settingsTitleItemIdentifier.rawValue)
        let settingsImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings".localized())
        settingsItem.activeImage = settingsImage
        settingsItem.inactiveImage = settingsImage

        insert(keyboardItem, viewController: KeyboardShortcutViewController())

        if let viewController = storyboard?.instantiateController(withIdentifier: ShortcutListViewController.className),
            let shortcutListViewController = viewController as? ShortcutListViewController {
            insert(appItem, viewController: shortcutListViewController)
        }

        if let viewController = storyboard?.instantiateController(withIdentifier: SettingsViewController.className),
            let settingsViewController = viewController as? SettingsViewController {
            insert(settingsItem, viewController: settingsViewController)
        }
    }

    func showKeyboardMapping() {
        guard let keyboardItem = titleView.items.first(where: {
            $0.identifier?.rawValue == keyboardTitleItemIdentifier.rawValue
        }) else { return }
        titleView.toggle(keyboardItem)
    }

}
