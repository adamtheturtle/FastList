import SwiftUI
import Testing
@_spi(FastListTesting) @testable import FastList

#if os(macOS)
import AppKit

private struct Row: Identifiable, Equatable {
    let id: Int
    let name: String
}

private final class CountingTableView: NSTableView {
    var reloadCount = 0

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }
}


private final class PartialReloadTableView: NSTableView {
    var partialReloadRowIndexes: [IndexSet] = []

    override func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        partialReloadRowIndexes.append(rowIndexes)
        super.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }
}

private final class DragRegistrationTableView: NSTableView {
    var localMask: NSDragOperation = []
    var externalMask: NSDragOperation = []

    override func setDraggingSourceOperationMask(_ mask: NSDragOperation, forLocal isLocal: Bool) {
        if isLocal {
            localMask = mask
        } else {
            externalMask = mask
        }
        super.setDraggingSourceOperationMask(mask, forLocal: isLocal)
    }
}

private final class SnapshotReloadTableView: NSTableView {
    var onReload: (() -> Void)?

    override func reloadData() {
        onReload?()
        super.reloadData()
    }

    override func rows(in _: NSRect) -> NSRange {
        NSRange(location: 0, length: 1)
    }
}

@MainActor
@Suite struct FastListCoordinatorTests {
    private func makeCoordinator(_ rows: [Row], selection: Set<Int> = []) -> FastList<Row>.Coordinator {
        let list = FastList(rows, selection: .constant(selection)) { Text($0.name) }
        return list.makeCoordinator()
    }

    @Test func buildsIDIndexWithoutATableView() {
        let coordinator = makeCoordinator([Row(id: 10, name: "a"), Row(id: 20, name: "b"), Row(id: 30, name: "c")])
        coordinator.reloadIfNeeded(
            [Row(id: 10, name: "a"), Row(id: 20, name: "b"), Row(id: 30, name: "c")], force: true
        )

        #expect(coordinator.index(of: 10) == 0)
        #expect(coordinator.index(of: 20) == 1)
        #expect(coordinator.index(of: 30) == 2)
        #expect(coordinator.index(of: 999) == nil)
    }

    @Test func reindexesAfterTheRowSetChanges() {
        let coordinator = makeCoordinator([])
        coordinator.reloadIfNeeded([Row(id: 1, name: "a"), Row(id: 2, name: "b")], force: true)
        #expect(coordinator.index(of: 2) == 1)

        coordinator.reloadIfNeeded([Row(id: 2, name: "b"), Row(id: 1, name: "a")], force: false)
        #expect(coordinator.index(of: 2) == 0)
        #expect(coordinator.index(of: 1) == 1)
    }

    @Test func rowContentIDForcesReloadWithoutChangingRows() {
        let table = CountingTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))

        var list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
            .rowContentID("one")
        let coordinator = list.makeCoordinator()
        coordinator.tableView = table
        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: true)
        #expect(table.reloadCount == 1)

        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: false)
        #expect(table.reloadCount == 1)

        list = list.rowContentID("two")
        coordinator.parent = list
        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: false)
        #expect(table.reloadCount == 2)
    }

    @Test func accessibilityRowPositionToggleForcesReload() {
        let table = CountingTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))

        var list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        let coordinator = list.makeCoordinator()
        coordinator.tableView = table
        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: true)
        #expect(table.reloadCount == 1)

        list = list.accessibilityRowPosition(true)
        coordinator.parent = list
        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: false)
        #expect(table.reloadCount == 2)

        coordinator.reloadIfNeeded([Row(id: 1, name: "a")], force: false)
        #expect(table.reloadCount == 2)
    }

    @Test func duplicateIDsKeepTheFirstIndex() {
        let coordinator = makeCoordinator([])
        coordinator.reloadIfNeeded([Row(id: 1, name: "first"), Row(id: 1, name: "dupe")], force: true)
        #expect(coordinator.index(of: 1) == 0)
        #expect(coordinator.numberOfRows(in: NSTableView()) == 1)
    }

    @Test func duplicateIDsRenderAndActivateOnlyTheFirstItem() {
        let rows = [
            Row(id: 1, name: "first"),
            Row(id: 1, name: "dupe"),
            Row(id: 2, name: "unique")
        ]
        var opened: Row?
        let list = FastList(rows, selection: .constant([])) { Text($0.name) }
            .onReturnKey { opened = $0 }
        #expect(list.items.map(\.name) == ["first", "unique"])

        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)
        table.selectRowIndexes([0], byExtendingSelection: false)

        #expect(coordinator.handleReturn())
        #expect(opened == Row(id: 1, name: "first"))
    }

    @Test func changingTheFirstDuplicateWinnerRefreshesNativeRows() {
        let table = CountingTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        var list = FastList(
            [Row(id: 1, name: "first"), Row(id: 1, name: "dupe")],
            selection: .constant([])
        ) { Text($0.name) }
        let coordinator = list.makeCoordinator()
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)
        #expect(table.reloadCount == 1)

        list = FastList(
            [Row(id: 1, name: "replacement"), Row(id: 1, name: "dupe")],
            selection: .constant([])
        ) { Text($0.name) }
        coordinator.parent = list
        coordinator.reloadIfNeeded(list.items, force: false)

        #expect(table.reloadCount == 2)
    }

    @Test func selectAllUpdatesTheSelectionBinding() {
        var sink: Set<Int> = []
        let binding = Binding<Set<Int>>(get: { sink }, set: { sink = $0 })
        let list = FastList(
            [Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")],
            selection: binding
        ) { Text($0.name) }
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        table.allowsMultipleSelection = true
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)

        #expect(coordinator.handleSelectAll())
        #expect(sink == [1, 2, 3])
        #expect(table.selectedRowIndexes == IndexSet([0, 1, 2]))
    }

    @Test func appliesSelectionToARealTableViewWithoutEchoing() {
        var sink: Set<Int> = []
        let binding = Binding<Set<Int>>(get: { sink }, set: { sink = $0 })
        let list = FastList([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")], selection: binding) {
            Text($0.name)
        }
        let coordinator = list.makeCoordinator()

        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")], force: true)

        coordinator.applySelection([1, 3])
        #expect(table.selectedRowIndexes == IndexSet([0, 2]))
        // applySelection must not write back into the binding (that's the ping-pong guard).
        #expect(sink.isEmpty)
    }

    @Test func removesSelectionIDsMissingFromTheNewSnapshot() {
        var sink: Set<Int> = [1, 3]
        let binding = Binding<Set<Int>>(get: { sink }, set: { sink = $0 })
        var list = FastList([Row(id: 1, name: "a"), Row(id: 3, name: "c")], selection: binding) {
            Text($0.name)
        }
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)
        #expect(table.selectedRowIndexes == IndexSet([0, 1]))

        list = FastList([Row(id: 1, name: "a"), Row(id: 2, name: "b")], selection: binding) {
            Text($0.name)
        }
        coordinator.parent = list
        coordinator.reloadIfNeeded(list.items, force: false)

        #expect(sink == [1])
        #expect(table.selectedRowIndexes == IndexSet(integer: 0))
        #expect(reconciledFastListSelection([1, 3], items: list.items) == [1])
    }

    @Test func reportsNilOnceWhenTheSnapshotBecomesEmpty() {
        var reported: [Int?] = []
        let list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
            .onTopRowChange { reported.append($0) }
        let coordinator = list.makeCoordinator()
        coordinator.reportTopRow(1)

        coordinator.reloadIfNeeded([], force: true)
        coordinator.reloadIfNeeded([], force: false)

        #expect(reported == [1, nil])
    }

    @Test func scrollObservationIsRemovedDuringTeardown() {
        let coordinator = makeCoordinator([])
        let container = FastListContainerView(frame: .zero)
        let scrollView = container.scrollView
        coordinator.installScrollObservers(for: scrollView)

        #expect(coordinator.observedScrollView === scrollView)
        #expect(scrollView.contentView.postsBoundsChangedNotifications)

        FastList<Row>.dismantleNSView(container, coordinator: coordinator)

        #expect(coordinator.observedScrollView == nil)
        #expect(!scrollView.contentView.postsBoundsChangedNotifications)
    }

    @Test func resetsPrefetchWatermarkWhenTheSnapshotChanges() {
        var prefetched: [[Row]] = []
        var list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
            .onPrefetchRows(count: 1) { prefetched.append($0) }
        let coordinator = list.makeCoordinator()
        let table = SnapshotReloadTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        table.onReload = {
            coordinator.scrollPositionChanged()
        }
        coordinator.reloadIfNeeded(
            (1 ... 5).map { Row(id: $0, name: "\($0)") },
            force: true
        )
        prefetched.removeAll()

        list = FastList((1 ... 3).map { Row(id: $0, name: "\($0)") }, selection: .constant([])) { Text($0.name) }
            .onPrefetchRows(count: 1) { prefetched.append($0) }
        coordinator.parent = list
        coordinator.reloadIfNeeded(list.items, force: false)

        #expect(!prefetched.isEmpty)
    }

    @Test func suppressesTopRowCallbacksWhileReplacingTheNativeSnapshot() {
        var reported: [Int?] = []
        var callbacksDuringReload = -1
        var list = FastList([Row(id: 1, name: "old")], selection: .constant([])) { Text($0.name) }
            .onTopRowChange { reported.append($0) }
        let coordinator = list.makeCoordinator()
        let table = SnapshotReloadTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)
        reported.removeAll()

        table.onReload = {
            coordinator.scrollPositionChanged()
            callbacksDuringReload = reported.count
        }
        list = FastList([Row(id: 2, name: "new")], selection: .constant([])) { Text($0.name) }
            .onTopRowChange { reported.append($0) }
        coordinator.parent = list
        coordinator.reloadIfNeeded(list.items, force: false)

        #expect(callbacksDuringReload == 0)
        #expect(reported == [2])
    }

    @Test func contextMenuRegistrationTracksUpdatedConfiguration() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        let coordinator = base.makeCoordinator()
        let table = NSTableView()

        coordinator.updateContextMenuRegistration(on: table)
        #expect(table.menu == nil)

        coordinator.parent = base.rowContextMenu { _, _ in [.button(title: "Open") {}] }
        coordinator.updateContextMenuRegistration(on: table)
        #expect(table.menu != nil)
        #expect(table.menu?.delegate === coordinator)

        coordinator.parent = base
        coordinator.updateContextMenuRegistration(on: table)
        #expect(table.menu == nil)
    }

    @Test func dragRegistrationTracksUpdatedConfiguration() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        let coordinator = base.makeCoordinator()
        let table = DragRegistrationTableView()

        coordinator.updateDragRegistration(on: table)
        #expect(table.localMask.isEmpty)
        #expect(table.externalMask.isEmpty)

        coordinator.parent = base.onRowDrag { _ in NSPasteboardItem() }
        coordinator.updateDragRegistration(on: table)
        #expect(table.localMask == [.copy, .generic])
        #expect(table.externalMask == .copy)

        coordinator.parent = base
        coordinator.updateDragRegistration(on: table)
        #expect(table.localMask.isEmpty)
        #expect(table.externalMask.isEmpty)
    }

    @Test func contextMenuActionsResolveAgainstTheCurrentSnapshot() {
        var opened: [String] = []
        var list = FastList([Row(id: 1, name: "original")], selection: .constant([])) { Text($0.name) }
            .rowContextMenu { row, _ in [.button(title: "Open") { opened.append(row.name) }] }
        let coordinator = list.makeCoordinator()
        coordinator.reloadIfNeeded(list.items, force: true)

        coordinator.performMenuAction(for: 1, entryIndex: 0)
        #expect(opened == ["original"])

        coordinator.reloadIfNeeded([], force: true)
        coordinator.performMenuAction(for: 1, entryIndex: 0)
        #expect(opened == ["original"])

        list = FastList([Row(id: 1, name: "replacement")], selection: .constant([])) { Text($0.name) }
            .rowContextMenu { row, _ in [.button(title: "Open") { opened.append(row.name) }] }
        coordinator.parent = list
        coordinator.reloadIfNeeded(list.items, force: true)
        coordinator.performMenuAction(for: 1, entryIndex: 0)
        #expect(opened == ["original", "replacement"])
    }


    @Test func hoverIndexClampsWhenTheRowSetShrinks() {
        let table = PartialReloadTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        let rows = [
            Row(id: 1, name: "a"),
            Row(id: 2, name: "b"),
            Row(id: 3, name: "c")
        ]
        var list = FastList(rows, selection: .constant([])) { Text($0.name) }
            .hoverHighlight(true)
        let coordinator = list.makeCoordinator()
        coordinator.tableView = table
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.reloadIfNeeded(rows, force: true)
        coordinator.updateHoveredRow(2, in: table)
        #expect(table.partialReloadRowIndexes.last == IndexSet(integer: 2))

        list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
            .hoverHighlight(true)
        coordinator.parent = list
        table.partialReloadRowIndexes.removeAll()
        coordinator.reloadIfNeeded(list.items, force: false)
        // Stale hover must not reload an out-of-bounds row.
        coordinator.updateHoveredRow(2, in: table)
        #expect(table.partialReloadRowIndexes.isEmpty)
    }

    @Test func contextMenuActionDoesNotRetargetWhenEntriesReorder() {
        var performed: [String] = []
        var list = FastList([Row(id: 1, name: "row")], selection: .constant([])) { Text($0.name) }
            .rowContextMenu { _, _ in
                [
                    .button(title: "Open") { performed.append("open") },
                    .button(title: "Delete") { performed.append("delete") }
                ]
            }
        let coordinator = list.makeCoordinator()
        coordinator.reloadIfNeeded(list.items, force: true)

        list = FastList(list.items, selection: .constant([])) { Text($0.name) }
            .rowContextMenu { _, _ in
                [
                    .button(title: "Delete") { performed.append("delete") },
                    .button(title: "Open") { performed.append("open") }
                ]
            }
        coordinator.parent = list

        // This represents clicking the first, “Open” item from the menu that was already visible.
        coordinator.performMenuAction(for: 1, entryIndex: 0, expectedTitle: "Open")
        #expect(performed.isEmpty)
    }
}

@MainActor
@Suite struct FastListReachEndTests {
    private func makeCoordinator(threshold: Int) -> FastList<Row>.Coordinator {
        let list = FastList([Row](), selection: .constant([])) { Text($0.name) }
            .onReachEnd(threshold: threshold) {}
        return list.makeCoordinator()
    }

    /// The bug: with a page size no larger than the threshold, the old edge-triggered
    /// `wasNearEnd` flag never cleared (the bottom stayed inside the threshold zone after the
    /// page landed), so paging died after exactly one page. Here a 20-row page with a
    /// threshold of 20 must keep paging.
    @Test func pagesRepeatedlyWhenThePageSizeEqualsTheThreshold() {
        let coordinator = makeCoordinator(threshold: 20)
        var count = 100
        var fires = 0

        // The user sits at the bottom; each fire appends a page of 20.
        for _ in 0 ..< 5
            where coordinator.consumeReachEnd(lastVisibleRow: count - 1, itemCount: count, threshold: 20) {
            fires += 1
            count += 20
        }

        #expect(fires == 5)
        #expect(count == 200)
    }

    /// The pathological case of the same bug: a page size of 1 never moved the bottom out of
    /// even a zero threshold zone.
    @Test func pagesRepeatedlyWithAPageSizeOfOne() {
        let coordinator = makeCoordinator(threshold: 0)
        var count = 10
        var fires = 0

        for _ in 0 ..< 4
            where coordinator.consumeReachEnd(lastVisibleRow: count - 1, itemCount: count, threshold: 0) {
            fires += 1
            count += 1
        }

        #expect(fires == 4)
        #expect(count == 14)
    }

    /// The per-frame `boundsDidChange` stream must not turn into a runaway paging loop: until
    /// the count actually moves, repeated calls are one fire.
    @Test func repeatedBoundsEventsAtTheSameCountFireOnce() {
        let coordinator = makeCoordinator(threshold: 5)
        var fires = 0
        for _ in 0 ..< 10 where coordinator.consumeReachEnd(lastVisibleRow: 99, itemCount: 100, threshold: 5) {
            fires += 1
        }
        #expect(fires == 1)
    }

    @Test func doesNotFireAwayFromTheEnd() {
        let coordinator = makeCoordinator(threshold: 5)
        #expect(!coordinator.consumeReachEnd(lastVisibleRow: 50, itemCount: 100, threshold: 5))
        // Exactly on the threshold boundary it does fire.
        #expect(coordinator.consumeReachEnd(lastVisibleRow: 94, itemCount: 100, threshold: 5))
    }

    @Test func doesNotFireOnAnEmptyOrOutOfRangeViewport() {
        let coordinator = makeCoordinator(threshold: 0)
        #expect(!coordinator.consumeReachEnd(lastVisibleRow: -1, itemCount: 0, threshold: 0))
        #expect(!coordinator.consumeReachEnd(lastVisibleRow: 5, itemCount: 3, threshold: 0))
    }

    /// Replacing the data (a filter, a refresh) re-arms the trigger even when the new list is
    /// shorter than the one that last fired.
    @Test func aShrinkingRowSetReArmsTheTrigger() {
        let coordinator = makeCoordinator(threshold: 0)
        #expect(coordinator.consumeReachEnd(lastVisibleRow: 99, itemCount: 100, threshold: 0))
        #expect(coordinator.consumeReachEnd(lastVisibleRow: 9, itemCount: 10, threshold: 0))
    }
}

@MainActor
@Suite struct FastListScrollToRowTests {
    private let rows = [Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")]

    private func makeCoordinator(
        scrollToID: Int?,
        rows: [Row]
    ) -> (FastList<Row>.Coordinator, NSTableView) {
        let list = FastList(rows, selection: .constant([])) { Text($0.name) }
            .scrollToRow(id: scrollToID)
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(rows, force: true)
        return (coordinator, table)
    }

    /// The bug: a caller who stores the anchor persistently never clears it, so every later
    /// `updateNSView` - one per selection change, one per `rowContentID` bump - yanked the viewport
    /// back to the anchor. ``FastList/scrollToRow(id:then:)`` documents a scroll that happens
    /// *once*, so only the first update may scroll.
    @Test func scrollsOnceForAPersistentTarget() {
        let (coordinator, table) = makeCoordinator(scrollToID: 3, rows: rows)

        #expect(coordinator.scrollToTargetIfNeeded(table))
        #expect(!coordinator.scrollToTargetIfNeeded(table))
        #expect(!coordinator.scrollToTargetIfNeeded(table))
    }

    @Test func doesNotScrollWithoutATarget() {
        let (coordinator, table) = makeCoordinator(scrollToID: nil, rows: rows)
        #expect(!coordinator.scrollToTargetIfNeeded(table))
    }

    /// A target whose row hasn't loaded yet stays pending, so it still scrolls once its page
    /// arrives rather than being silently consumed.
    @Test func aTargetNotYetLoadedStaysPending() {
        let (coordinator, table) = makeCoordinator(scrollToID: 99, rows: rows)
        #expect(!coordinator.scrollToTargetIfNeeded(table))

        coordinator.reloadIfNeeded(rows + [Row(id: 99, name: "z")], force: false)
        #expect(coordinator.scrollToTargetIfNeeded(table))
        #expect(!coordinator.scrollToTargetIfNeeded(table))
    }

    /// Clearing the target (via `then`) and setting the same id again scrolls again - "once"
    /// is per request, not per id for the lifetime of the list.
    @Test func clearingTheTargetReArmsTheSameID() {
        var list = FastList(rows, selection: .constant([])) { Text($0.name) }
            .scrollToRow(id: 3)
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(rows, force: true)

        #expect(coordinator.scrollToTargetIfNeeded(table))

        list = list.scrollToRow(id: nil)
        coordinator.parent = list
        #expect(!coordinator.scrollToTargetIfNeeded(table))

        list = list.scrollToRow(id: 3)
        coordinator.parent = list
        #expect(coordinator.scrollToTargetIfNeeded(table))
    }
}

@MainActor
@Suite struct FastListReturnKeyTests {
    private let rows = [Row(id: 1, name: "a"), Row(id: 2, name: "b")]

    private func makeCoordinator(
        onReturnKey: ((Row) -> Void)?,
        selectedRow: Int?
    ) -> FastList<Row>.Coordinator {
        var list = FastList(rows, selection: .constant([])) { Text($0.name) }
        if let onReturnKey { list = list.onReturnKey(onReturnKey) }
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(rows, force: true)
        if let selectedRow { table.selectRowIndexes([selectedRow], byExtendingSelection: false) }
        return coordinator
    }

    /// The bug: `KeyHandlingTableView` always swallowed Return because `handleReturn` gave it
    /// no way to say it had declined the event, so a list with no `onReturnKey` blocked (for
    /// example) a sheet's default button. Declining must be reported so the table can fall
    /// through to `super.keyDown(with:)`.
    @Test func declinesReturnWithoutAHandler() {
        let coordinator = makeCoordinator(onReturnKey: nil, selectedRow: 0)
        #expect(!coordinator.handleReturn())
    }

    @Test func declinesReturnWithNothingSelected() {
        let coordinator = makeCoordinator(onReturnKey: { _ in }, selectedRow: nil)
        #expect(!coordinator.handleReturn())
    }

    @Test func consumesReturnAndOpensTheSelectedRow() {
        var opened: Row?
        let coordinator = makeCoordinator(onReturnKey: { opened = $0 }, selectedRow: 1)

        #expect(coordinator.handleReturn())
        #expect(opened == rows[1])
    }

    /// The whole point of the fix: a declined Return must reach `super.keyDown(with:)` and so
    /// carry on up the responder chain, where (in the reported bug) a sheet's default button is
    /// waiting. A consumed one must not.
    @Test func declinedReturnReachesTheResponderChain() {
        let (table, container) = makeTableInResponderChain()

        table.onReturn = { false }
        table.keyDown(with: .returnKeyDown)
        #expect(container.sawEvent)

        container.sawEvent = false
        table.onReturn = { true }
        table.keyDown(with: .returnKeyDown)
        #expect(!container.sawEvent)
    }

    /// A key the table doesn't special-case always travels on, handler or not.
    @Test func otherKeysAlwaysReachTheResponderChain() {
        let (table, container) = makeTableInResponderChain()
        table.onReturn = { true }
        table.keyDown(with: .otherKeyDown)
        #expect(container.sawEvent)
    }

    /// A `KeyHandlingTableView` whose next responder records anything that gets past it.
    private func makeTableInResponderChain() -> (KeyHandlingTableView, EventRecordingView) {
        let table = KeyHandlingTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        let container = EventRecordingView()
        container.addSubview(table)
        return (table, container)
    }
}

/// A superview - and so next responder - that records any key event the table passes on.
/// `NSTableView`'s own `keyDown` routes an unhandled key up the responder chain either as the
/// raw event or as an interpreted command selector, so both paths are recorded.
private final class EventRecordingView: NSView {
    var sawEvent = false

    override func keyDown(with _: NSEvent) {
        sawEvent = true
    }

    override func doCommand(by _: Selector) {
        sawEvent = true
    }

    override func noResponder(for _: Selector) {
        sawEvent = true
    }
}

private extension NSEvent {
    static var returnKeyDown: NSEvent { keyDown(keyCode: 36) }
    static var otherKeyDown: NSEvent { keyDown(keyCode: 0) }

    static func keyDown(keyCode: UInt16) -> NSEvent {
        // swiftlint:disable:next force_unwrapping
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

@MainActor
@Suite struct FastListModifierTests {
    @Test func modifiersReturnConfiguredCopies() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        #expect(base.configuration.onDoubleClick == nil)
        #expect(base.configuration.trailingSwipe == nil)

        let configured = base
            .onDoubleClick { _ in }
            .onReturnKey { _ in }
            .swipeActions(edge: .trailing) { _ in [] }
            .rowContextMenu { _, _ in [] }
            .rowContentID("content")

        #expect(configured.configuration.onDoubleClick != nil)
        #expect(configured.configuration.onReturnKey != nil)
        #expect(configured.configuration.trailingSwipe != nil)
        #expect(configured.configuration.contextMenu != nil)
        #expect(configured.configuration.rowContentID == AnyHashable("content"))
        // The original value is untouched (value semantics).
        #expect(base.configuration.onDoubleClick == nil)
        #expect(base.configuration.rowContentID == nil)
    }

    @Test func onReachEndStoresThresholdAndAction() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        #expect(base.configuration.onReachEnd == nil)
        #expect(base.configuration.reachEndThreshold == 0)

        let configured = base.onReachEnd(threshold: 10) {}
        #expect(configured.configuration.onReachEnd != nil)
        #expect(configured.configuration.reachEndThreshold == 10)
        // Untouched original (value semantics).
        #expect(base.configuration.onReachEnd == nil)
    }

    @Test func swipeEdgeRoutesToTheRightSlot() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        let leading = base.swipeActions(edge: .leading) { _ in [SwipeAction(title: "Flag") {}] }
        #expect(leading.configuration.leadingSwipe != nil)
        #expect(leading.configuration.trailingSwipe == nil)
    }
}

@MainActor
@Suite struct FastListSelectionModeTests {
    /// What a configured table's selection behavior actually comes out as: the AppKit flag plus
    /// the two delegate answers that decide whether a selection can happen at all.
    private struct TableSelectionState {
        var allowsMultipleSelection: Bool
        var allowsSelection: Bool
        var allowsRowSelection: Bool
    }

    /// Regression test for the single-selection binding collapsing a multi-row selection to an
    /// arbitrary (hash-ordered) row: the table must be single-selection so the multi-row
    /// selection can never form.

    @Test func shiftRangeSelectionRequiresMultipleMode() {
        var selected: Int? = 1
        let binding = Binding<Int?>(get: { selected }, set: { selected = $0 })
        let single = FastList([Row(id: 1, name: "a"), Row(id: 2, name: "b")], selection: binding) {
            Text($0.name)
        }
        #expect(!single.makeCoordinator().testingAllowsShiftRangeSelection)

        let multiple = FastList(
            [Row(id: 1, name: "a"), Row(id: 2, name: "b")],
            selection: .constant(Set<Int>())
        ) { Text($0.name) }
        #expect(multiple.makeCoordinator().testingAllowsShiftRangeSelection)
    }

    @Test func singleSelectionBindingUsesSingleSelectionMode() {
        var selected: Int?
        let binding = Binding<Int?>(get: { selected }, set: { selected = $0 })
        let list = FastList([Row(id: 7, name: "a")], selection: binding) { Text($0.name) }

        #expect(list.configuration.selectionMode == .single)
        #expect(!tableSelectionState(for: list).allowsMultipleSelection)
    }

    /// Regression test for the "non-selectable" list being selectable: the table must refuse
    /// selection outright rather than discarding the write into a `.constant` binding, which
    /// leaves AppKit's highlight on screen forever.
    @Test func nonSelectableListRefusesSelection() {
        let list = FastList([Row(id: 1, name: "a"), Row(id: 2, name: "b")]) { Text($0.name) }
        #expect(list.configuration.selectionMode == .none)

        let state = tableSelectionState(for: list)
        #expect(!state.allowsMultipleSelection)
        #expect(!state.allowsSelection)
        #expect(!state.allowsRowSelection)
    }

    @Test func multipleSelectionListStaysMultiSelect() {
        let list = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        #expect(list.configuration.selectionMode == .multiple)

        let state = tableSelectionState(for: list)
        #expect(state.allowsMultipleSelection)
        #expect(state.allowsSelection)
        #expect(state.allowsRowSelection)
    }

    /// Builds the real `NSTableView` the representable would build and reports what its
    /// selection behavior actually ends up as, delegate included.
    private func tableSelectionState(for list: FastList<Row>) -> TableSelectionState {
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        coordinator.reloadIfNeeded(list.items, force: true)
        // The same call `makeNSView` / `updateNSView` make; a real `Context` can't be built in
        // a unit test, so drive the table configuration directly.
        list.configureSelection(for: table)

        return TableSelectionState(
            allowsMultipleSelection: table.allowsMultipleSelection,
            allowsSelection: coordinator.selectionShouldChange(in: table),
            allowsRowSelection: coordinator.tableView(table, shouldSelectRow: 0)
        )
    }

    @Test func singleSelectionBindingBridgesToASet() {
        var selected: Int?
        let binding = Binding<Int?>(get: { selected }, set: { selected = $0 })
        let list = FastList([Row(id: 7, name: "a")], selection: binding) { Text($0.name) }

        list.$selection.wrappedValue = [7]
        #expect(selected == 7)

        list.$selection.wrappedValue = []
        #expect(selected == nil)
    }
}


@MainActor
@Suite struct FastListHoverTrackingTests {
    @Test func trackingAreaIncludesMouseEnteredAndExited() {
        let table = KeyHandlingTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        table.updateTrackingAreas()
        let options = table.trackingAreas.map(\.options)
        #expect(options.contains { $0.contains(.mouseEnteredAndExited) })
        #expect(options.contains { $0.contains(.mouseMoved) })
    }
}

#endif
