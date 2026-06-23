//
//  FastList.swift
//  FastList
//

import AppKit
import SwiftUI

/// A drop-in replacement for SwiftUI's `List` on macOS, backed by `NSTableView`.
///
/// SwiftUI's `List` / `Table` rebuild every visible row's body on each selection change and
/// stall badly on large data sets — selecting a row in a list of a few thousand items can
/// hang for seconds. `FastList` instead materializes and recycles only the *visible* rows
/// the way Mail's message list does, so selection and scrolling stay instant no matter how
/// long the list is.
///
/// ```swift
/// FastList(rows, selection: $selection) { row in
///     RowView(row)
/// }
/// .onDoubleClick { open($0) }
/// .onReturnKey { open($0) }
/// .swipeActions(edge: .trailing) { row in
///     [SwipeAction(title: "Delete", role: .destructive) { delete(row) }]
/// }
/// ```
///
/// ## Hit-testing
///
/// Each row hosts its SwiftUI content in an `NSHostingView`. For native table selection to
/// work, the hosted content must be **hit-transparent except for its own interactive
/// controls** — apply `.allowsHitTesting(false)` to the non-interactive parts so a left
/// click falls through to the table. Interactive controls inside the row (a toggle, a
/// star) still receive their clicks normally.
public struct FastList<Item: Identifiable>: NSViewRepresentable where Item.ID: Hashable {
    /// The rows to show, already filtered and sorted by the caller.
    let items: [Item]
    @Binding var selection: Set<Item.ID>
    let rowContent: (Item) -> AnyView
    var configuration = FastListConfiguration<Item>()

    // MARK: Initializers

    /// Creates a list with a multiple-selection binding.
    ///
    /// - Parameters:
    ///   - items: The rows to display, already filtered and sorted.
    ///   - selection: A binding to the set of selected row ids.
    ///   - row: Builds the SwiftUI content for a row. Make the non-interactive parts
    ///     hit-transparent (see the type's discussion).
    public init(
        _ items: [Item],
        selection: Binding<Set<Item.ID>>,
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        self.items = items
        _selection = selection
        rowContent = { AnyView(row($0)) }
    }

    /// Creates a list with a single-selection binding.
    public init(
        _ items: [Item],
        selection: Binding<Item.ID?>,
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        self.init(
            items,
            selection: Binding(
                get: { selection.wrappedValue.map { [$0] } ?? [] },
                set: { selection.wrappedValue = $0.first }
            ),
            row: row
        )
    }

    /// Creates a non-selectable list.
    public init(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        self.init(items, selection: .constant([]), row: row)
    }

    // MARK: Modifiers

    /// Opens an item when it's double-clicked.
    public func onDoubleClick(_ action: @escaping (Item) -> Void) -> Self {
        copy { $0.onDoubleClick = action }
    }

    /// Opens the selected item when Return or keypad Enter is pressed.
    public func onReturnKey(_ action: @escaping (Item) -> Void) -> Self {
        copy { $0.onReturnKey = action }
    }

    /// Adds swipe actions to one edge of every row.
    ///
    /// - Parameters:
    ///   - edge: The edge the actions are revealed from. Defaults to `.trailing`.
    ///   - actions: Builds the actions for a given row. Return an empty array for rows that
    ///     should have no swipe on this edge.
    public func swipeActions(
        edge: HorizontalEdge = .trailing,
        _ actions: @escaping (Item) -> [SwipeAction]
    ) -> Self {
        copy {
            switch edge {
            case .leading: $0.leadingSwipe = actions
            case .trailing: $0.trailingSwipe = actions
            }
        }
    }

    /// Adds a native right-click menu to every row. The closure decides the menu for a
    /// given row (reading your own selection for single-row vs. multi-selection menus).
    public func rowContextMenu(_ items: @escaping (Item) -> [MenuItem]) -> Self {
        copy { $0.contextMenu = items }
    }

    /// Makes rows draggable. Return the pasteboard payload for a row, or `nil` to make that
    /// row non-draggable. Built at the AppKit layer because the hosted SwiftUI content is
    /// hit-transparent, which disables a SwiftUI `.draggable`.
    public func onRowDrag(_ pasteboardItem: @escaping (Item) -> NSPasteboardItem?) -> Self {
        copy { $0.pasteboardItem = pasteboardItem }
    }

    /// Observes the lifetime of a row drag — `began` receives the dragging session so the
    /// host can inspect its pasteboard and react (e.g. reveal a drop zone), `ended` fires on
    /// drop or cancel. Keeps app-specific pasteboard types out of the list itself.
    public func onDragSession(
        began: @escaping (NSDraggingSession) -> Void,
        ended: @escaping () -> Void = {}
    ) -> Self {
        copy {
            $0.onDragSessionBegan = began
            $0.onDragSessionEnded = ended
        }
    }

    /// Reports the id of the row at the top of the viewport whenever a user scroll settles,
    /// so you can persist and restore the free-scroll position across launches. `nil` when
    /// the list is empty.
    public func onTopRowChange(_ action: @escaping (Item.ID?) -> Void) -> Self {
        copy { $0.onTopRowChange = action }
    }

    /// Scrolls a row into view once (e.g. a restored selection on launch). `then` is called
    /// after the scroll has been honored so you can clear the target.
    public func scrollToRow(id: Item.ID?, then: @escaping () -> Void = {}) -> Self {
        copy {
            $0.scrollToID = id
            $0.onScrolledToID = then
        }
    }

    private func copy(_ mutate: (inout FastListConfiguration<Item>) -> Void) -> Self {
        var copy = self
        mutate(&copy.configuration)
        return copy
    }

    // MARK: NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let table = KeyHandlingTableView()
        table.headerView = nil
        table.style = .inset
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        let column = NSTableColumn(identifier: .fastListColumn)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.handleDoubleClick)
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.handleReturn() }

        // Drive the right-click menu through the table's own `menu` property (populated
        // lazily in `menuNeedsUpdate`) rather than overriding `menu(for:)`, so AppKit's
        // native contextual-menu machinery runs and draws the focus-ring outline around a
        // right-clicked row that isn't selected. Only install it when a menu is configured,
        // so right-clicking an unconfigured list shows nothing.
        if configuration.contextMenu != nil {
            let rowMenu = NSMenu()
            rowMenu.delegate = context.coordinator
            table.menu = rowMenu
        }

        if configuration.pasteboardItem != nil {
            table.setDraggingSourceOperationMask([.copy, .generic], forLocal: true)
            table.setDraggingSourceOperationMask(.copy, forLocal: false)
        }

        context.coordinator.tableView = table
        context.coordinator.reloadIfNeeded(items, force: true)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // Report the top visible row when a user scroll settles. didEndLiveScroll fires once
        // per gesture — far cheaper than streaming every bounds change. The observer
        // auto-unregisters when the coordinator deallocates (macOS 10.11+).
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.liveScrollEnded),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scroll
        )
        return scroll
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.tableView else { return }

        // Only reload when the row set actually changed (filter/sort/refresh) — never on a
        // bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(items, force: false)
        coordinator.applySelection(selection)

        if let scrollToID = configuration.scrollToID, let row = coordinator.index(of: scrollToID) {
            table.scrollRowToVisible(row)
            DispatchQueue.main.async { configuration.onScrolledToID?() }
        }
    }
}
