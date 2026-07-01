//
//  FastList.swift
//  FastList
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// A drop-in replacement for SwiftUI's `List`, backed by `NSTableView` on macOS for
/// large-list performance and by a native SwiftUI `List` on iOS / iPadOS.
///
/// SwiftUI's `List` and `Table` rebuild every visible row's body on each selection change and
/// slow down sharply on large data sets. Selecting a row in a list of a few thousand items can
/// hang for seconds. `FastList` instead materializes and recycles only the visible rows the
/// way Mail's message list does, so selection and scrolling stay fast no matter how long the
/// list is.
///
/// ```swift
/// FastList(rows, selection: $selection) { row in
///     RowView(row)
///         .allowsHitTesting(false) // let clicks fall through to the table
/// }
/// .onDoubleClick { open($0) }
/// .onReturnKey { open($0) }
/// .swipeActions(edge: .trailing) { row in
///     [SwipeAction(title: "Delete", role: .destructive) { delete(row) }]
/// }
/// ```
///
/// ## Selection
///
/// Pass a binding to drive selection, or omit it for a non-selectable list. `rows` is any
/// `[Item]` where `Item: Identifiable`; filter and sort it yourself before handing it over,
/// because `FastList` renders exactly what you pass.
///
/// ```swift
/// FastList(rows, selection: $selectedIDs) { RowView($0) }  // Binding<Set<ID>>
/// FastList(rows, selection: $selectedID)  { RowView($0) }  // Binding<ID?>
/// FastList(rows) { RowView($0) }                           // no selection
/// ```
///
/// ## Hit-testing
///
/// Each row hosts its SwiftUI content in an `NSHostingView`. For native table selection to
/// work, the non-interactive parts of the row need to be hit-transparent: apply
/// `.allowsHitTesting(false)` to them so a left click falls through to the table. Interactive
/// controls inside the row (a `Toggle`, a favorite star `Button`) still receive their clicks
/// normally; just avoid making the whole row swallow clicks.
///
/// ## How it works
///
/// - One `NSTableColumn`, header hidden, with automatic row heights by default so it behaves
///   like a single-column `List` with variable-height rows. Fixed-format rows can opt into
///   ``rowHeight(_:)`` to skip intrinsic-height measurement during scroll.
/// - Rows are recycled `NSTableCellView`s, each hosting your SwiftUI view in an
///   `NSHostingView` sized to its intrinsic content height.
/// - The coordinator keeps an id-to-row index so selection and ``scrollToRow(id:then:)`` are
///   O(1), and a re-entrancy guard stops the SwiftUI binding and the table's selection from
///   ping-ponging.
/// - `reloadData` runs only when the row set changes (filter, sort, refresh), not on a bare
///   selection change.
public struct FastList<Item: Identifiable> where Item.ID: Hashable {
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

    /// Adds swipe actions to one edge of every row, rendered as `NSTableViewRowAction`s.
    ///
    /// ```swift
    /// .swipeActions(edge: .leading) { row in
    ///     [SwipeAction(title: "Flag", tint: .yellow, systemImage: "flag.fill") { flag(row) }]
    /// }
    /// .swipeActions(edge: .trailing) { row in
    ///     [SwipeAction(title: "Delete", role: .destructive, systemImage: "trash") { delete(row) }]
    /// }
    /// ```
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

    /// Adds a native right-click menu to every row. The closure runs per right-clicked row,
    /// so you can build single-row or multi-selection menus by reading your own selection
    /// state.
    ///
    /// ```swift
    /// .rowContextMenu { row in
    ///     [.button(title: "Open") { open(row) },
    ///      .separator,
    ///      .button(title: "Delete", isEnabled: row.isDeletable) { delete(row) }]
    /// }
    /// ```
    public func rowContextMenu(_ items: @escaping (Item) -> [MenuItem]) -> Self {
        copy { $0.contextMenu = items }
    }

    /// Makes rows draggable on iOS/iPadOS by returning a `URL` payload (e.g. a pad's web
    /// URL), or `nil` for a non-draggable row. Drives a native SwiftUI `.draggable`, so a
    /// row can be dragged into Safari, Notes, or a Split View. On macOS the richer
    /// ``onRowDrag(_:)`` pasteboard path is used instead, so this is a no-op there.
    public func onRowDragURL(_ url: @escaping (Item) -> URL?) -> Self {
        copy { $0.dragURL = url }
    }

    /// Makes rows draggable. Return the pasteboard payload for a row, or `nil` to make that
    /// row non-draggable.
    ///
    /// The payload is built at the AppKit layer because the hosted SwiftUI content is
    /// hit-transparent, which disables a SwiftUI `.draggable`.
    ///
    /// ```swift
    /// .onRowDrag { row in
    ///     let item = NSPasteboardItem()
    ///     item.setString(row.url.absoluteString, forType: .URL)
    ///     return item            // return nil to make a row non-draggable
    /// }
    /// ```
    #if os(macOS)
    public func onRowDrag(_ pasteboardItem: @escaping (Item) -> NSPasteboardItem?) -> Self {
        copy { $0.pasteboardItem = pasteboardItem }
    }
    #endif

    /// Observes the lifetime of a row drag. `began` receives the dragging session so the host
    /// can inspect its pasteboard and react (for example, reveal a drop zone); `ended` fires
    /// on drop or cancel. Keeps app-specific pasteboard types out of the list itself.
    ///
    /// ```swift
    /// .onDragSession(began: { session in revealDropZoneIfNeeded(session) },
    ///                ended: { hideDropZone() })
    /// ```
    #if os(macOS)
    public func onDragSession(
        began: @escaping (NSDraggingSession) -> Void,
        ended: @escaping () -> Void = {}
    ) -> Self {
        copy {
            $0.onDragSessionBegan = began
            $0.onDragSessionEnded = ended
        }
    }
    #endif

    /// Reports the id of the row at the top of the viewport whenever a user scroll settles,
    /// so you can persist and restore the free-scroll position across launches. The id is
    /// `nil` when the list is empty.
    ///
    /// Pair it with ``scrollToRow(id:then:)`` to restore the position on the next launch:
    ///
    /// ```swift
    /// .onTopRowChange { topID in defaults.scrollAnchor = topID }
    /// ```
    public func onTopRowChange(_ action: @escaping (Item.ID?) -> Void) -> Self {
        copy { $0.onTopRowChange = action }
    }

    /// Reloads visible rows when `id` changes, even if the item id sequence is unchanged.
    ///
    /// `FastList` normally avoids `reloadData` unless row ids change, so selection-only
    /// updates stay cheap. Use this when row content depends on external state not captured
    /// by `items`, such as favorite ids or read/unread state.
    public func reloadID(_ id: some Hashable) -> Self {
        copy { $0.reloadID = AnyHashable(id) }
    }

    /// Uses a fixed row height on the macOS `NSTableView` backend.
    ///
    /// By default `FastList` uses AppKit's automatic row heights so arbitrary SwiftUI row
    /// content can size itself. Fixed-format rows can opt into a concrete height to avoid
    /// intrinsic-height measurement while rows recycle during fast scrolling. This is a no-op
    /// on the iOS/iPadOS SwiftUI `List` backend.
    public func rowHeight(_ height: CGFloat?) -> Self {
        copy { $0.rowHeight = height }
    }

    /// Fires when the last visible row comes within `threshold` rows of the end of the data
    /// as a user scroll settles — the trigger for load-more / infinite-scroll paging.
    ///
    /// Unlike ``onTopRowChange``, this reflects the *bottom* of the viewport, so it fires
    /// correctly on any window size without estimating the visible-row count from row
    /// heights. A `threshold` of `0` fires only once the very last row is on screen; a larger
    /// threshold loads the next page before the user hits the bottom.
    ///
    /// ```swift
    /// .onReachEnd(threshold: 10) { loadNextPage() }
    /// ```
    ///
    /// - Parameters:
    ///   - threshold: How many rows from the end the last visible row must reach before
    ///     firing. Defaults to `0` (the last row must be visible).
    ///   - perform: Runs when the bottom of the viewport reaches the threshold.
    public func onReachEnd(threshold: Int = 0, perform: @escaping () -> Void) -> Self {
        copy {
            $0.reachEndThreshold = threshold
            $0.onReachEnd = perform
        }
    }

    /// Scrolls a row into view once (for example, a restored selection on launch). `then` is
    /// called after the scroll has been honored so you can clear the target.
    ///
    /// ```swift
    /// .scrollToRow(id: restoredAnchor) { restoredAnchor = nil }
    /// ```
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

    // MARK: NSViewRepresentable (macOS)

    #if os(macOS)
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let table = KeyHandlingTableView()
        table.headerView = nil
        table.style = .inset
        configureRowHeight(for: table)
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
        // Track the scroll position via the content view's bounds. boundsDidChange fires for
        // EVERY scroll — trackpad, mouse wheel, scrollbar, and keyboard — so onReachEnd (load-more)
        // and onTopRowChange work regardless of input device. didEndLiveScroll alone only covers
        // the end of a trackpad gesture, which silently stranded mouse-wheel users on the first
        // page. The coordinator de-dupes onTopRowChange so the per-frame stream isn't wasteful.
        // Observers auto-unregister when the coordinator deallocates (macOS 10.11+).
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollPositionChanged),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        // Also fire once when a trackpad gesture's momentum fully settles, so the final resting
        // position is reported even if the last bounds change landed mid-deceleration.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollPositionChanged),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scroll
        )
        return scroll
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.tableView else { return }

        configureRowHeight(for: table)
        // Only reload when the row set actually changed (filter/sort/refresh) — never on a
        // bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(items, force: false)
        coordinator.applySelection(selection)

        if let scrollToID = configuration.scrollToID, let row = coordinator.index(of: scrollToID) {
            table.scrollRowToVisible(row)
            DispatchQueue.main.async { configuration.onScrolledToID?() }
        }
    }

    private func configureRowHeight(for table: NSTableView) {
        if let rowHeight = configuration.rowHeight {
            table.usesAutomaticRowHeights = false
            if table.rowHeight != rowHeight { table.rowHeight = rowHeight }
        } else {
            table.usesAutomaticRowHeights = true
        }
    }
    #endif
}

#if os(macOS)
    extension FastList: NSViewRepresentable {}
#else
    // MARK: View (iOS / iPadOS)

    /// The iPad backend: a native SwiftUI `List`. SwiftUI's `List` is `UITableView`-backed
    /// and recycles rows, so the large-list selection cost that motivated the AppKit
    /// `NSTableView` path on macOS isn't a problem here - the platform list is already
    /// fast. Selection (driving a `NavigationSplitView` detail), per-row swipe actions, and
    /// the per-row context menu map straight onto the same `FastList` configuration. The
    /// macOS-only affordances - double-click / Return-to-open (iPad opens via selection),
    /// AppKit row dragging, and free-scroll anchor restore - are intentionally not wired
    /// here yet.
    extension FastList: View {
        public var body: some View {
            List(selection: $selection) {
                ForEach(items) { item in
                    row(for: item)
                }
            }
            // `.plain`, with a custom selection background (see `selectionBackground`).
            // The earlier `.sidebar` style insets selection nicely when the list IS the
            // primary sidebar column, but a non-sidebar *content* column on iPad lays its
            // rows out shifted under the leading edge, clipping the first characters of
            // each row. `.plain` lays out correctly; its default selection is a full-bleed
            // rectangle that runs edge to edge and slides behind the `NavigationSplitView`
            // sidebar, so we suppress it via `.listRowBackground` and draw our own inset,
            // rounded-rectangle highlight instead — no bleed, no clipping.
            .listStyle(.plain)
        }

        /// The per-row selection highlight: an inset, rounded-rectangle fill when the row
        /// is selected and clear otherwise. Supplying it as the row background replaces the
        /// plain list's default full-bleed selection, keeping the highlight off the column's
        /// leading/trailing edges (so it can't bleed behind the split-view sidebar) and
        /// inside the row (so it can't clip the row's content).
        @ViewBuilder
        private func selectionBackground(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                Color.clear
            }
        }

        @ViewBuilder
        private func row(for item: Item) -> some View {
            let leading = configuration.leadingSwipe?(item) ?? []
            let trailing = configuration.trailingSwipe?(item) ?? []
            let menu = configuration.contextMenu?(item) ?? []
            let dragURL = configuration.dragURL?(item)

            let base = rowContent(item)
                .tag(item.id)
                .listRowBackground(selectionBackground(isSelected: selection.contains(item.id)))
                .swipeActions(edge: .leading) { swipeButtons(leading) }
                .swipeActions(edge: .trailing) { swipeButtons(trailing) }

            // Only attach a context menu when one is configured, so unconfigured rows
            // don't long-press into an empty menu.
            let withMenu = Group {
                if menu.isEmpty {
                    base
                } else {
                    base.contextMenu { contextButtons(menu) }
                }
            }

            // A draggable row (drag a pad/question URL into Safari, Notes, or Split View)
            // when a URL payload is configured.
            if let dragURL {
                withMenu.draggable(dragURL)
            } else {
                withMenu
            }
        }

        @ViewBuilder
        private func swipeButtons(_ actions: [SwipeAction]) -> some View {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(role: action.role == .destructive ? .destructive : nil) {
                    action.action()
                } label: {
                    if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
                .tint(action.tint)
            }
        }

        @ViewBuilder
        private func contextButtons(_ items: [MenuItem]) -> some View {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case let .button(title, isEnabled, role, action):
                    Button(role: role == .destructive ? .destructive : nil, action: action) {
                        Text(title)
                    }
                    .disabled(!isEnabled)
                case .separator:
                    Divider()
                }
            }
        }
    }
#endif
