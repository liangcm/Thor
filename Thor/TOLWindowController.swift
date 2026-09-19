//
//  TOLWindowController.swift
//  Thor
//
//  Created by AlvinZhu on 4/18/16.
//  Copyright © 2016 AlvinZhu. All rights reserved.
//

import Cocoa

class TOLWindowController: NSWindowController {

    var titleView       = TitleView()
    var identifiers     = [NSToolbarItem.Identifier]()
    var items           = [NSToolbarItem.Identifier: NSToolbarItem]()
    var viewControllers = [String: NSViewController]()

    override func windowDidLoad() {
        super.windowDidLoad()

        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.appearance = NSAppearance(named: .darkAqua)
        window?.isOpaque = false
        window?.backgroundColor = NSColor.black.withAlphaComponent(0.82)
        window?.isMovableByWindowBackground = true
        window?.toolbarStyle = .unifiedCompact

        let toolbar = NSToolbar(identifier: "toolbar")
        toolbar.delegate = self
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar

        // title

        titleView.toggleCallback = toggleViewControllers

        let titleItem = NSToolbarItem(itemIdentifier: titleViewIdentifier)
        titleItem.view = titleView

        identifiers.append(titleViewIdentifier)
        items[titleViewIdentifier] = titleItem
        toolbar.insertItem(withItemIdentifier: titleViewIdentifier, at: 0)

        // space

        let spaceItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.flexibleSpace)

        identifiers.append(NSToolbarItem.Identifier.flexibleSpace)
        items[NSToolbarItem.Identifier.flexibleSpace] = spaceItem
        toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 0)
    }

    override func keyDown(with theEvent: NSEvent) {
        let key = theEvent.charactersIgnoringModifiers
        if theEvent.modifierFlags.contains(NSEvent.ModifierFlags.command) && key == "w" {
            close()
        } else {
            super.keyDown(with: theEvent)
        }
    }

    func insert(_ titleItem: TitleViewItem, viewController: NSViewController) {
        viewControllers[titleItem.identifier!.rawValue] = viewController

        titleView.insert(titleItem)
        titleView.toggle(titleView.items.first!)
    }

    private func toggleViewControllers(_ item: TitleViewItem) {
        if let contentViewController = contentViewController, contentViewController.children.count > 0 {
            contentViewController.view.subviews.forEach { $0.removeFromSuperview() }
            contentViewController.children.forEach { $0.removeFromParent() }
        }

        if let viewController = viewControllers[item.identifier!.rawValue] {
            contentViewController?.insertChild(viewController, at: 0)
            contentViewController?.view.addSubview(viewController.view)
            contentViewController?.view.frame = viewController.view.frame
            window?.setContentSize(viewController.view.frame.size)
        }
    }

}

extension TOLWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return identifiers
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        return items[itemIdentifier]
    }

}

// MARK: -

class TitleView: NSView {

    var items = [TitleViewItem]()
    var toggleCallback: ((_ item: TitleViewItem) -> Void)?

    func insert(_ item: TitleViewItem) {
        items.append(item)
        items.forEach { $0.removeFromSuperview() }
        for (idx, item) in items.enumerated() {
            addSubview(item)

            item.target = self
            item.action = #selector(TitleView.toggle(_:))
            item.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                item.leftAnchor.constraint(equalTo: leftAnchor, constant: CGFloat(idx) * titleItemWidth),
                item.topAnchor.constraint(equalTo: topAnchor),
                item.widthAnchor.constraint(equalToConstant: titleItemWidth),
                item.heightAnchor.constraint(equalToConstant: titleItemHeight)
            ])
        }

        frame = CGRect(x: 0, y: 0, width: CGFloat(items.count) * titleItemWidth, height: titleItemHeight)
    }

    @objc func toggle(_ sender: TitleViewItem) {
        items.forEach { $0.setSelected($0 == sender) }

        toggleCallback?(sender)
    }
}

// MARK: -

class TitleViewItem: NSButton {

    var activeImage: NSImage? {
        get { return image }
        set { image = newValue }
    }

    var inactiveImage: NSImage? {
        get { return alternateImage }
        set { alternateImage = newValue }
    }

    init(itemIdentifier: String) {
        super.init(frame: NSRect.zero)

        identifier = NSUserInterfaceItemIdentifier(rawValue: itemIdentifier)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor.white.withAlphaComponent(0.72)
        setButtonType(.toggle)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        state = selected ? .off : .on
        layer?.backgroundColor = selected ?
            NSColor.white.withAlphaComponent(0.14).cgColor :
            NSColor.clear.cgColor
        contentTintColor = selected ?
            NSColor.white.withAlphaComponent(0.94) :
            NSColor.white.withAlphaComponent(0.42)
    }

}
