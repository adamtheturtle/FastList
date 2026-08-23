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
        /// Last applied accessibility row-position flag, so toggling the modifier reloads cells.
        private var accessibilityIncludesRowPosition = false
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
        /// The highest row index included in the last prefetch callback.
        private var lastPrefetchedThroughRow = -1
        /// De-dupes ``onVisibleRowRangeChange`` callbacks.
        private var lastVisibleRowRange: ClosedRange<Int>?
        private var hoveredRow = -1
        /// Anchor for shift-click range selection.
        private var selectionAnchorRow: Int?
        /// Rows being dragged for an in-list reorder.
        private var draggingRowIndexes = IndexSet()

        @_spi(FastListTesting)
        public var testingAllowsShiftRangeSelection: Bool {
            parent.configuration.selectionMode == .multiple
        }

        /// Visible for tests that remapping survives `reloadIfNeeded`.
        @_spi(FastListTesting)
        public var testingSelectionAnchorRow: Int? {
            selectionAnchorRow
        }

        /// Sets the shift-selection anchor for tests without synthesizing modifier flags.
        @_spi(FastListTesting)
        public func testingSetSelectionAnchorRow(_ row: Int?) {
            selectionAnchorRow = row
        }

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
            let dragEnabled = parent.configuration.pasteboardItem != nil
            let reorderEnabled = parent.configuration.onMoveRows != nil
            var localMask: NSDragOperation = []
            if dragEnabled {
                localMask.formUnion([.copy, .generic])
            }
            if reorderEnabled {
                localMask.insert(.move)
            }
            tableView.setDraggingSourceOperationMask(localMask, forLocal: true)
            tableView.setDraggingSourceOperationMask(dragEnabled ? .copy : [], forLocal: false)
            if reorderEnabled || parent.configuration.onRowDrop != nil {
                var types: [NSPasteboard.PasteboardType] = [.string]
                if parent.configuration.onRowDrop != nil {
                    types.append(contentsOf: [.URL, .fileURL, .tiff, .png])
                }
                tableView.registerForDraggedTypes(types)
            }
        }

        func reloadIfNeeded(_ newItems: [Item], force: Bool) {
            let newItems = deduplicatedFastListItems(newItems)
            let nextRowContentID = parent.configuration.rowContentID
            let nextAccessibilityIncludesRowPosition = parent.configuration.accessibilityIncludesRowPosition
            let previousIDs = items.map(\.id)
            let previousRowContentID = rowContentID
            let previousAccessibilityIncludesRowPosition = accessibilityIncludesRowPosition
            let anchorID = selectionAnchorRow.flatMap { items.indices.contains($0) ? items[$0].id : nil }
            let itemsChanged = newItems.map(\.id) != previousIDs
            let contentTokenChanged = nextRowContentID != previousRowContentID
                || nextAccessibilityIncludesRowPosition != previousAccessibilityIncludesRowPosition
            let changed = force
                || parent.containedDuplicateIDs
                || itemsChanged
                || contentTokenChanged
            items = newItems
            rowContentID = nextRowContentID
            accessibilityIncludesRowPosition = nextAccessibilityIncludesRowPosition
            indexByID = Dictionary(
                newItems.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            // Drop a hover index that no longer exists after a filter/delete shrinks the list.
            if hoveredRow >= items.count {
                hoveredRow = -1
            }
            selectionAnchorRow = anchorID.flatMap { indexByID[$0] }
            if itemsChanged {
                let oldIDs = items.map(\.id)
                let newIDs = newItems.map(\.id)
                let isPureAppend = newIDs.count > oldIDs.count
                    && Array(newIDs.prefix(oldIDs.count)) == oldIDs
                if !isPureAppend {
                    lastPrefetchedThroughRow = -1
                }
            }
            let reconciledSelection = reconciledFastListSelection(parent.selection, items: newItems)
            if reconciledSelection != parent.selection { parent.selection = reconciledSelection }
            if newItems.isEmpty { reportTopRow(nil) }
            if newItems.isEmpty { lastVisibleRowRange = nil }
            guard changed else { return }

            isApplyingSnapshot = true
            // `reloadData` clears native selection and can synchronously notify the delegate.
            // Keep the binding isolated from that transient empty state until the live IDs
            // have been restored below.
            isApplyingSelection = true
            applySnapshotToTable(
                oldIDs: previousIDs,
                newIDs: newItems.map(\.id),
                forceFullReload: force || parent.containedDuplicateIDs || contentTokenChanged
            )
            // reloadData / animated updates can drop selection; restore it from the binding.
            applySelection(reconciledSelection)
            isApplyingSelection = false
            isApplyingSnapshot = false

            // Reconcile once from the settled native viewport. Any synchronous notifications
            // emitted by reloadData were deliberately ignored above.
            scrollPositionChanged()
        }

        /// Applies an incremental animated insert/delete when only identities were added or
        /// removed in-order; otherwise falls back to `reloadData`.
        func applySnapshotToTable(
            oldIDs: [Item.ID],
            newIDs: [Item.ID],
            forceFullReload: Bool
        ) {
            guard let tableView else { return }

            if !forceFullReload {
                let diff = FastListAnimatedDiff.difference(from: oldIDs, to: newIDs)
                if diff.supportsIncrementalUpdate {
                    tableView.beginUpdates()
                    if !diff.deletions.isEmpty {
                        tableView.removeRows(at: diff.deletions, withAnimation: .effectFade)
                    }
                    if !diff.insertions.isEmpty {
                        tableView.insertRows(at: diff.insertions, withAnimation: .effectFade)
                    }
                    tableView.endUpdates()
                    return
                }
            }

            tableView.reloadData()
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
            cell.wantsLayer = true
            cell.rowIndex = row
            cell.enclosingTableView = tableView
            cell.onHeightChange = { [weak cell, weak tableView] in
                guard let cell, let tableView else { return }
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: cell.rowIndex))
            }
            var content = parent.rowContent(items[row])
            if parent.configuration.accessibilityIncludesRowPosition {
                content = AnyView(
                    content.accessibilityValue("\(row + 1) of \(items.count)")
                )
            }
            cell.host(content)
            if parent.configuration.highlightsRowsOnHover, row == hoveredRow {
                cell.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor
            } else {
                cell.layer?.backgroundColor = nil
            }
            return cell
        }

        func updateHoveredRow(_ row: Int, in tableView: NSTableView) {
            guard parent.configuration.highlightsRowsOnHover else { return }
            let clamped = items.indices.contains(row) ? row : -1
            guard clamped != hoveredRow else { return }

            let rowsToRefresh = IndexSet([hoveredRow, clamped].filter { items.indices.contains($0) })
            hoveredRow = clamped
            guard !rowsToRefresh.isEmpty else { return }
            tableView.reloadData(forRowIndexes: rowsToRefresh, columnIndexes: IndexSet(integer: 0))
        }

        /// Recomputes hover from the current pointer location so scrolling under a stationary
        /// cursor still highlights the row now under the mouse.
        func refreshHoveredRowFromPointer(in tableView: NSTableView) {
            guard parent.configuration.highlightsRowsOnHover,
                  let window = tableView.window else { return }

            let point = tableView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let row = tableView.visibleRect.contains(point) ? tableView.row(at: point) : -1
            updateHoveredRow(row, in: tableView)
        }

        public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard items.indices.contains(row) else { return nil }

            if let item = parent.configuration.pasteboardItem?(items[row]) {
                return item
            }
            guard parent.configuration.onMoveRows != nil else { return nil }
            let placeholder = NSPasteboardItem()
            placeholder.setString("fastlist-reorder:\(row)", forType: .string)
            return placeholder
        }

        public func tableView(
            _: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt _: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            draggingRowIndexes = rowIndexes
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

        /// Refuses selection when the list was created without a binding, so AppKit never
        /// draws a highlight, rather than drawing one and relying on a write-back that a
        /// binding with nowhere to write can never undo.
        public func selectionShouldChange(in _: NSTableView) -> Bool {
            parent.configuration.selectionMode != .none
        }

        /// Backstop for the programmatic selection paths that bypass
        /// ``selectionShouldChange(in:)``, so a non-selectable list stays non-selectable.
        /// Also implements shift-click range selection on macOS.
        public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard parent.configuration.selectionMode != .none else { return false }
            guard items.indices.contains(row) else { return false }

            if parent.configuration.selectionMode == .multiple,
               NSEvent.modifierFlags.contains(.shift),
               let anchor = selectionAnchorRow,
               anchor >= 0 {
                let range = min(anchor, row) ... max(anchor, row)
                // Do not set `isApplyingSelection`: `selectRowIndexes` must notify
                // `tableViewSelectionDidChange` so the SwiftUI binding stays in sync.
                tableView.selectRowIndexes(IndexSet(integersIn: range), byExtendingSelection: false)
                return false
            }

            if !NSEvent.modifierFlags.contains(.command) {
                selectionAnchorRow = row
            }
            return true
        }

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
            announceSelectionChange(count: ids.count)
        }

        private func announceSelectionChange(count: Int) {
            guard parent.configuration.accessibilityAnnouncesSelectionChanges else { return }
            let message = count == 1 ? "1 row selected" : "\(count) rows selected"
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
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

        @discardableResult
        func handleSelectAll() -> Bool {
            guard let tableView, tableView.allowsMultipleSelection, !items.isEmpty else { return false }
            let allIDs = Set(items.map(\.id))
            applySelection(allIDs)
            if parent.selection != allIDs {
                parent.selection = allIDs
                announceSelectionChange(count: allIDs.count)
            }
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

            if let onVisibleRowRangeChange = parent.configuration.onVisibleRowRangeChange {
                let range = visible.location ... (visible.location + visible.length - 1)
                if range != lastVisibleRowRange {
                    lastVisibleRowRange = range
                    onVisibleRowRangeChange(range)
                }
            }

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

            prefetchIfNeeded(lastVisibleRow: NSMaxRange(visible) - 1)
            refreshHoveredRowFromPointer(in: tableView)
        }

        private func prefetchIfNeeded(lastVisibleRow: Int) {
            guard let onPrefetchRows = parent.configuration.onPrefetchRows,
                  items.indices.contains(lastVisibleRow) else { return }

            let target = min(lastVisibleRow + parent.configuration.prefetchRowCount, items.count - 1)
            guard target > lastPrefetchedThroughRow else { return }

            let start = lastPrefetchedThroughRow + 1
            guard start <= target else { return }

            lastPrefetchedThroughRow = target
            onPrefetchRows(Array(items[start ... target]))
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

        // MARK: Drop destination

        public func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            if parent.configuration.onMoveRows != nil,
               info.draggingSource as AnyObject? === tableView {
                if dropOperation == .above {
                    return .move
                }
                tableView.setDropRow(row, dropOperation: .above)
                return .move
            }
            guard let validate = parent.configuration.validateRowDrop else { return [] }
            if dropOperation != .above {
                tableView.setDropRow(row, dropOperation: .above)
            }
            return validate(info, row)
        }

        public func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation _: NSTableView.DropOperation
        ) -> Bool {
            if let onMove = parent.configuration.onMoveRows,
               info.draggingSource as AnyObject? === tableView,
               !draggingRowIndexes.isEmpty {
                onMove(draggingRowIndexes, row)
                draggingRowIndexes = IndexSet()
                return true
            }
            return parent.configuration.onRowDrop?(info, row) ?? false
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
            for (entryIndex, entry) in builder(items[row], parent.selection).enumerated() {
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

            let entries = builder(items[row], parent.selection)
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
