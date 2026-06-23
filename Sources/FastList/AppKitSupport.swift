//
//  AppKitSupport.swift
//  FastList
//
//  The AppKit helpers backing ``FastList`` — the key-handling table subclass, the
//  SwiftUI-hosting cell, and the reuse identifiers. Module-internal.
//

import AppKit
import SwiftUI

/// `NSTableView` subclass that forwards Return / keypad-Enter to a handler (to open the
/// selected row) while leaving arrow-key row navigation to AppKit. The per-row right-click
/// menu is the table's own `menu` property, populated lazily by the coordinator's
/// `menuNeedsUpdate(_:)` so AppKit draws the native right-clicked-row focus ring.
final class KeyHandlingTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Only show the menu — and let AppKit run its native right-clicked-row highlight —
        // when the click lands on a row, not the empty area below the list. `super` sets
        // `clickedRow`, draws the outline, and returns `menu`, whose items the coordinator
        // fills in via `menuNeedsUpdate(_:)`.
        let point = convert(event.locationInWindow, from: nil)
        guard row(at: point) >= 0 else { return nil }

        return super.menu(for: event)
    }
}

/// A table cell that hosts a row's SwiftUI content in an `NSHostingView`, sized to the
/// content's intrinsic height so `usesAutomaticRowHeights` lays the row out correctly.
final class HostingCellView: NSTableCellView {
    private var hosting: NSHostingView<AnyView>?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func host(_ view: AnyView) {
        if let hosting {
            hosting.rootView = view
            return
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = .intrinsicContentSize
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hosting = hostingView
    }
}

/// Carries a menu item's closure as an `NSMenuItem.representedObject`, so a single `@objc`
/// action can dispatch any item.
final class MenuActionBox {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }
}

extension NSUserInterfaceItemIdentifier {
    static let fastListCell = NSUserInterfaceItemIdentifier("FastListHostingCell")
    static let fastListColumn = NSUserInterfaceItemIdentifier("FastListColumn")
}
