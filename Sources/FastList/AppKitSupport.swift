#if os(macOS)
//
//  AppKitSupport.swift
//  FastList
//
//  The AppKit helpers backing ``FastList`` - the key-handling table subclass, the
//  SwiftUI-hosting cell, and the reuse identifiers. Module-internal.
//

import AppKit
import SwiftUI

/// `NSTableView` subclass that forwards Return / keypad-Enter to a handler (to open the
/// selected row) while leaving arrow-key row navigation to AppKit. The per-row right-click
/// menu is the table's own `menu` property, populated lazily by the coordinator's
/// `menuNeedsUpdate(_:)` so AppKit draws the native right-clicked-row focus ring.
final class KeyHandlingTableView: NSTableView {
    /// Handles Return / keypad Enter, returning whether it consumed the event. Returning
    /// `false` (no `onReturnKey` configured, or nothing selected) means the event was not
    /// handled here.
    var onReturn: (() -> Bool)?
    /// Reports the row under the mouse, or `-1` when the pointer left the table.
    var onHoveredRowChanged: ((Int) -> Void)?
    /// Selects every row when the user presses Command-A. Return whether the event was consumed.
    var onSelectAll: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoveredRowChanged?(row(at: point))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoveredRowChanged?(-1)
        super.mouseExited(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a",
           onSelectAll?() == true {
            return
        }
        // 36 = Return, 76 = keypad Enter.
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        // Fall through to the responder chain whenever the handler declines the event, so a
        // list without `onReturnKey` doesn't swallow Return and leave, say, a sheet's default
        // button unreachable while the table has focus.
        guard isReturn, onReturn?() == true else {
            super.keyDown(with: event)
            return
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Only show the menu - and let AppKit run its native right-clicked-row highlight -
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
    var rowIndex = 0
    weak var enclosingTableView: NSTableView?
    var onHeightChange: (() -> Void)?
    private var lastReportedHeight: CGFloat = 0

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard let hosting else { return }
        let height = hosting.fittingSize.height
        guard abs(height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = height
        let notify = onHeightChange
        RunLoop.main.perform {
            notify?()
        }
    }

    func host(_ view: AnyView) {
        if let hosting {
            hosting.rootView = view
            needsLayout = true
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
#endif
