import AppKit
import SwiftUI
import Testing
@testable import FastList

private struct Row: Identifiable, Equatable {
    let id: Int
    let name: String
}

@MainActor
@Suite struct FastListCoordinatorTests {
    private func makeCoordinator(_ rows: [Row], selection: Set<Int> = []) -> FastList<Row>.Coordinator {
        let list = FastList(rows, selection: .constant(selection)) { Text($0.name) }
        return list.makeCoordinator()
    }

    @Test func buildsIDIndexWithoutATableView() {
        let coordinator = makeCoordinator([Row(id: 10, name: "a"), Row(id: 20, name: "b"), Row(id: 30, name: "c")])
        coordinator.reloadIfNeeded([Row(id: 10, name: "a"), Row(id: 20, name: "b"), Row(id: 30, name: "c")], force: true)

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

    @Test func duplicateIDsKeepTheFirstIndex() {
        let coordinator = makeCoordinator([])
        coordinator.reloadIfNeeded([Row(id: 1, name: "first"), Row(id: 1, name: "dupe")], force: true)
        #expect(coordinator.index(of: 1) == 0)
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
            .rowContextMenu { _ in [] }

        #expect(configured.configuration.onDoubleClick != nil)
        #expect(configured.configuration.onReturnKey != nil)
        #expect(configured.configuration.trailingSwipe != nil)
        #expect(configured.configuration.contextMenu != nil)
        // The original value is untouched (value semantics).
        #expect(base.configuration.onDoubleClick == nil)
    }

    @Test func swipeEdgeRoutesToTheRightSlot() {
        let base = FastList([Row(id: 1, name: "a")], selection: .constant([])) { Text($0.name) }
        let leading = base.swipeActions(edge: .leading) { _ in [SwipeAction(title: "Flag") {}] }
        #expect(leading.configuration.leadingSwipe != nil)
        #expect(leading.configuration.trailingSwipe == nil)
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
