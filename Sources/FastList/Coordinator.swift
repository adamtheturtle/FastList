#if os(macOS)
//
//  Coordinator.swift
//  FastList
//

import AppKit
import SwiftUI

extension FastList {
    @preconcurrency @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FastList
        weak var tableView: NSTableView?
        private var items: [Item] = []
        private var indexByID: [Item.ID: Int] = [:]
        /// Guards against the selection binding and the table's selection ping-ponging.
        private var isApplyingSelection = false
        /// The last top row reported to `onTopRowChange`. The scroll callback now fires on every
        /// bounds change (so it covers mouse-wheel/scrollbar/keyboard scrolls, not just trackpad
        /// gestures), and this de-dupes those per-frame events down to one call per actual change.
        private var lastTopRowID: Item.ID?

        init(_ parent: FastList) {
            self.parent = parent
        }

        /// Xcode 26.5's SIL optimizer (EarlyPerfInliner) crashes while optimizing this
        /// generic Coordinator's destructor in a Release build. An explicit,
        /// optimization-opted-out deinit sidesteps the compiler bug; the member-wise
        /// teardown it would otherwise synthesize is unchanged.
        @_optimize(none)
        deinit {}

        // MARK: Data

        func reloadIfNeeded(_ newItems: [Item], force: Bool) {
            let changed = force || newItems.map(\.id) != items.map(\.id)
            items = newItems
            indexByID = Dictionary(
                newItems.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            guard changed else { return }

            tableView?.reloadData()
            // reloadData drops the selection; restore it from the binding.
            applySelection(parent.selection)
        }

        func index(of id: Item.ID) -> Int? {
            indexByID[id]
        }

        public func numberOfRows(in _: NSTableView) -> Int {
            items.count
        }

        public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: .fastListCell, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: .fastListCell)
            cell.host(parent.rowContent(items[row]))
            return cell
        }

        public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard items.indices.contains(row) else { return nil }

            return parent.configuration.pasteboardItem?(items[row])
        }

        public func tableView(
            _: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt _: NSPoint,
            forRowIndexes _: IndexSet
        ) {
            parent.configuration.onDragSessionBegan?(session)
        }

        public func tableView(
            _: NSTableView,
            draggingSession _: NSDraggingSession,
            endedAt _: NSPoint,
            operation _: NSDragOperation
        ) {
            parent.configuration.onDragSessionEnded?()
        }

        // MARK: Selection

        /// Push the binding's selection into the table without echoing it back.
        func applySelection(_ ids: Set<Item.ID>) {
            guard let tableView else { return }

            let rows = IndexSet(ids.compactMap { indexByID[$0] })
            guard rows != tableView.selectedRowIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            isApplyingSelection = false
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView = notification.object as? NSTableView else { return }

            let ids = Set(tableView.selectedRowIndexes.compactMap {
                items.indices.contains($0) ? items[$0].id : nil
            })
            if ids != parent.selection { parent.selection = ids }
        }

        // MARK: Actions

        @objc func handleDoubleClick() {
            guard let tableView, tableView.clickedRow >= 0,
                  items.indices.contains(tableView.clickedRow) else { return }

            parent.configuration.onDoubleClick?(items[tableView.clickedRow])
        }

        func handleReturn() {
            guard let tableView, let row = tableView.selectedRowIndexes.first,
                  items.indices.contains(row) else { return }

            parent.configuration.onReturnKey?(items[row])
        }

        /// The scroll position changed — report the row now at the top of the viewport (when it
        /// actually changes), and whether the bottom of the viewport has neared the end of the
        /// data (for load-more paging).
        ///
        /// Fires on every `boundsDidChange`, so it covers scrolling by **any** input — trackpad,
        /// mouse wheel, scrollbar, keyboard — not just the trackpad gesture-end that
        /// `didEndLiveScroll` reports. `onTopRowChange` is de-duped against `lastTopRowID` so the
        /// per-frame bounds stream collapses to one call per real change; `onReachEnd` consumers
        /// are expected to guard their own re-entrancy (e.g. an "already loading" flag).
        @objc func scrollPositionChanged() {
            guard let tableView else { return }

            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else { return }

            if let onTopRowChange = parent.configuration.onTopRowChange,
               items.indices.contains(visible.location) {
                let topID = items[visible.location].id
                if topID != lastTopRowID {
                    lastTopRowID = topID
                    onTopRowChange(topID)
                }
            }

            if let onReachEnd = parent.configuration.onReachEnd {
                let lastVisible = NSMaxRange(visible) - 1
                if items.indices.contains(lastVisible),
                   lastVisible >= items.count - 1 - parent.configuration.reachEndThreshold {
                    onReachEnd()
                }
            }
        }

        // MARK: Swipe actions

        public func tableView(
            _: NSTableView,
            rowActionsForRow row: Int,
            edge: NSTableView.RowActionEdge
        ) -> [NSTableViewRowAction] {
            guard items.indices.contains(row) else { return [] }

            let item = items[row]
            let builder = edge == .leading
                ? parent.configuration.leadingSwipe
                : parent.configuration.trailingSwipe
            let actions = builder?(item) ?? []
            return actions.map { action in
                let rowAction = NSTableViewRowAction(
                    style: action.role == .destructive ? .destructive : .regular,
                    title: action.title
                ) { [weak self] _, _ in
                    action.action()
                    self?.tableView?.rowActionsVisible = false
                }
                if let tint = action.tint { rowAction.backgroundColor = NSColor(tint) }
                // An image replaces the title on the revealed button; the title stays set so
                // VoiceOver still announces the action.
                if let symbol = action.systemImage {
                    rowAction.image = NSImage(systemSymbolName: symbol, accessibilityDescription: action.title)
                }
                return rowAction
            }
        }

        // MARK: Context menu

        /// Populate the table's persistent context menu for the row the user right-clicked.
        /// Driving the menu through the table's own `menu` property plus this delegate lets
        /// AppKit's native contextual-menu machinery draw the focus-ring outline around a
        /// right-clicked row that isn't selected. `clickedRow` is set before the menu opens.
        public func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let row = tableView?.clickedRow ?? -1
            guard items.indices.contains(row), let builder = parent.configuration.contextMenu else { return }

            menu.autoenablesItems = false
            for entry in builder(items[row]) {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case let .button(title, isEnabled, action):
                    let menuItem = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.isEnabled = isEnabled
                    menuItem.representedObject = MenuActionBox(action)
                    menu.addItem(menuItem)
                }
            }
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuActionBox)?.perform()
        }
    }
}
#endif
