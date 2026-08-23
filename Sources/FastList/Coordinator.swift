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
        weak var containerView: FastListContainerView?
        private(set) weak var observedScrollView: NSScrollView?
        private var items: [Item] = []
        private var indexByID: [Item.ID: Int] = [:]
        private var rowContentID: AnyHashable?
        /// Guards against the selection binding and the table's selection ping-ponging.
        private var isApplyingSelection = false
        /// Native reloads can synchronously move the viewport while AppKit is still reconciling
        /// rows. Ignore those transient scroll notifications until both mappings agree again.
        private var isApplyingSnapshot = false
        /// The last top row reported to `onTopRowChange`. The scroll callback now fires on every
        /// bounds change (so it covers mouse-wheel/scrollbar/keyboard scrolls, not just trackpad
        /// gestures), and this de-dupes those per-frame events down to one call per actual change.
        private var lastTopRowID: Item.ID?
        /// Shared with the native SwiftUI backend so every platform has identical once-per-count
        /// paging semantics.
        private var reachEndGate = FastListReachEndGate()
        /// The id `scrollToRow(id:)` last scrolled to, so a target that stays set across updates
        /// scrolls once rather than on every update. Cleared when the target goes back to `nil`,
        /// so re-setting the same id later scrolls again.
        private var lastScrolledToID: Item.ID?

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

        /// Keeps AppKit's drag-source registration aligned with the current modifier value.
        func updateDragRegistration(on tableView: NSTableView) {
            let isEnabled = parent.configuration.pasteboardItem != nil
            tableView.setDraggingSourceOperationMask(isEnabled ? [.copy, .generic] : [], forLocal: true)
            tableView.setDraggingSourceOperationMask(isEnabled ? .copy : [], forLocal: false)
        }

        func reloadIfNeeded(_ newItems: [Item], force: Bool) {
            let newItems = deduplicatedFastListItems(newItems)
            let nextRowContentID = parent.configuration.rowContentID
            let changed = force
                || parent.containedDuplicateIDs
                || newItems.map(\.id) != items.map(\.id)
                || nextRowContentID != rowContentID
            items = newItems
            rowContentID = nextRowContentID
            indexByID = Dictionary(
                newItems.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let reconciledSelection = reconciledFastListSelection(parent.selection, items: newItems)
            if reconciledSelection != parent.selection { parent.selection = reconciledSelection }
            if newItems.isEmpty { reportTopRow(nil) }
            guard changed else { return }

            isApplyingSnapshot = true
            // `reloadData` clears native selection and can synchronously notify the delegate.
            // Keep the binding isolated from that transient empty state until the live IDs
            // have been restored below.
            isApplyingSelection = true
            tableView?.reloadData()
            // reloadData drops the selection; restore it from the binding.
            applySelection(reconciledSelection)
            isApplyingSelection = false
            isApplyingSnapshot = false

            // Reconcile once from the settled native viewport. Any synchronous notifications
            // emitted by reloadData were deliberately ignored above.
            scrollPositionChanged()
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

            let wasApplyingSelection = isApplyingSelection
            isApplyingSelection = true
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            isApplyingSelection = wasApplyingSelection
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

        /// Opens the selected row, if there is one and a handler is configured.
        ///
        /// - Returns: Whether the key press was consumed. `false` means the caller should pass
        ///   the event on to `super.keyDown(with:)` so the responder chain still sees it - so a
        ///   `FastList` with no `onReturnKey` doesn't swallow Return and block, say, a sheet's
        ///   default button.
        @discardableResult
        func handleReturn() -> Bool {
            guard let onReturnKey = parent.configuration.onReturnKey,
                  let tableView, let row = tableView.selectedRowIndexes.first,
                  items.indices.contains(row) else { return false }

            onReturnKey(items[row])
            return true
        }

        // MARK: Scrolling to a row

        /// Scrolls to ``FastListConfiguration/scrollToID`` if that target hasn't been honored
        /// yet, implementing ``FastList/scrollToRow(id:then:)``'s documented "once" semantics.
        ///
        /// - Returns: Whether a scroll was performed, i.e. whether `then` should now be called.
        @discardableResult
        func scrollToTargetIfNeeded(_ tableView: NSTableView) -> Bool {
            guard let id = parent.configuration.scrollToID else {
                // The target was cleared, so a later re-set of the same id counts as new.
                lastScrolledToID = nil
                return false
            }
            // Check the row exists *before* recording the target: an id that isn't loaded yet
            // must stay pending so it still scrolls once its page arrives.
            guard id != lastScrolledToID, let row = index(of: id) else { return false }

            lastScrolledToID = id
            tableView.scrollRowToVisible(row)
            return true
        }

        /// The scroll position changed - report the row now at the top of the viewport (when it
        /// actually changes), and whether the bottom of the viewport has neared the end of the
        /// data (for load-more paging).
        ///
        /// Fires on every `boundsDidChange`, so it covers scrolling by **any** input - trackpad,
        /// mouse wheel, scrollbar, keyboard - not just the trackpad gesture-end that
        /// `didEndLiveScroll` reports. `onTopRowChange` is de-duped against `lastTopRowID` so the
        /// per-frame bounds stream collapses to one call per real change; `onReachEnd` consumers
        /// are expected to guard their own re-entrancy (e.g. an "already loading" flag).
        @objc func scrollPositionChanged() {
            guard !isApplyingSnapshot, let tableView else { return }

            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else { return }

            if let onTopRowChange = parent.configuration.onTopRowChange,
               items.indices.contains(visible.location) {
                let topID = items[visible.location].id
                reportTopRow(topID, using: onTopRowChange)
            }

            if let onReachEnd = parent.configuration.onReachEnd {
                if consumeReachEnd(
                    lastVisibleRow: NSMaxRange(visible) - 1,
                    itemCount: items.count,
                    threshold: parent.configuration.reachEndThreshold
                ) {
                    onReachEnd()
                }
            } else {
                reachEndGate.reset()
            }
        }

        /// Reports a changed top-row identity. Keeping the last non-empty ID lets a later
        /// empty snapshot emit `nil` exactly once, matching `onTopRowChange`'s contract.
        func reportTopRow(_ id: Item.ID?, using callback: ((Item.ID?) -> Void)? = nil) {
            guard id != lastTopRowID else { return }

            lastTopRowID = id
            (callback ?? parent.configuration.onTopRowChange)?(id)
        }

        /// Whether the viewport's bottom has reached the load-more threshold *and* the list has
        /// changed since the trigger last fired.
        ///
        /// De-duping on the row count rather than on an "was already near the end" edge is what
        /// makes paging work for **any** page size. With an edge flag, a page no larger than the
        /// threshold leaves the bottom still inside the threshold zone after it lands, so the
        /// flag never clears and the trigger never re-fires - paging dies after one page for a
        /// page size <= the threshold (and immediately for a page size of 1). Keyed on the count,
        /// every landed page re-arms the trigger, while the per-frame bounds stream can't re-fire
        /// it because the count doesn't move until a page actually arrives.
        ///
        /// Any change in the count re-arms, not just growth, so replacing the data (a filter or a
        /// refresh that shrinks the list) can page again too.
        ///
        /// - Returns: Whether `onReachEnd` should fire now. Firing is recorded, so a second call
        ///   at the same count returns `false`.
        func consumeReachEnd(lastVisibleRow: Int, itemCount: Int, threshold: Int) -> Bool {
            reachEndGate.consume(
                lastVisibleRow: lastVisibleRow,
                itemCount: itemCount,
                threshold: threshold
            )
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

        /// Keeps the native menu registration aligned with the current SwiftUI value.
        func updateContextMenuRegistration(on tableView: NSTableView) {
            guard parent.configuration.contextMenu != nil else {
                tableView.menu = nil
                return
            }

            let rowMenu = tableView.menu ?? NSMenu()
            rowMenu.delegate = self
            tableView.menu = rowMenu
        }

        /// Populate the table's persistent context menu for the row the user right-clicked.
        /// Driving the menu through the table's own `menu` property plus this delegate lets
        /// AppKit's native contextual-menu machinery draw the focus-ring outline around a
        /// right-clicked row that isn't selected. `clickedRow` is set before the menu opens.
        public func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let row = tableView?.clickedRow ?? -1
            guard items.indices.contains(row), let builder = parent.configuration.contextMenu else { return }

            let itemID = items[row].id
            menu.autoenablesItems = false
            for (entryIndex, entry) in builder(items[row]).enumerated() {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case let .button(title, isEnabled, _, _):
                    let menuItem = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.isEnabled = isEnabled
                    menuItem.representedObject = MenuActionBox { [weak self] in
                        self?.performMenuAction(for: itemID, entryIndex: entryIndex, expectedTitle: title)
                    }
                    menu.addItem(menuItem)
                }
            }
        }

        /// Re-resolves a menu action against the live snapshot so a menu left open across a
        /// deletion cannot invoke an action for an item that no longer exists.
        func performMenuAction(for itemID: Item.ID, entryIndex: Int, expectedTitle: String? = nil) {
            guard let row = indexByID[itemID], items.indices.contains(row),
                  let builder = parent.configuration.contextMenu else { return }

            let entries = builder(items[row])
            guard entries.indices.contains(entryIndex),
                  case let .button(title, isEnabled, _, action) = entries[entryIndex],
                  expectedTitle == nil || title == expectedTitle,
                  isEnabled else { return }

            action()
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuActionBox)?.perform()
        }
    }
}

extension FastList.Coordinator {
    // MARK: Scroll observation lifecycle

    func installScrollObservers(for scrollView: NSScrollView) {
        removeScrollObservers()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollPositionChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollPositionChanged),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
    }

    func removeScrollObservers() {
        guard let scrollView = observedScrollView else { return }

        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        scrollView.contentView.postsBoundsChangedNotifications = false
        observedScrollView = nil
    }
}
#endif
