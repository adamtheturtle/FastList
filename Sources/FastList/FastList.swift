//
//  FastList.swift
//  FastList
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// Keeps native row indices and SwiftUI identities unambiguous. The first item supplied for
/// an ID wins, preserving caller order while dropping later duplicates.
func deduplicatedFastListItems<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
    var seenIDs = Set<Item.ID>()
    return items.filter { seenIDs.insert($0.id).inserted }
}

/// Removes selection IDs that are no longer represented by the current item snapshot.
func reconciledFastListSelection<Item: Identifiable>(
    _ selection: Set<Item.ID>,
    items: [Item]
) -> Set<Item.ID> where Item.ID: Hashable {
    selection.intersection(Set(items.map(\.id)))
}

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
/// Pass a set binding to drive multiple selection. `rows` is any
/// `[Item]` where `Item: Identifiable`; filter and sort it yourself before handing it over,
/// because `FastList` renders exactly what you pass.
///
/// ```swift
/// FastList(rows, selection: $selectedIDs) { RowView($0) }  // Binding<Set<ID>>
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
/// - One `NSTableColumn`, header hidden, with automatic row heights so it behaves like a
///   single-column `List` with variable-height rows.
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
    /// Duplicate input is exceptional and must refresh native cells on every update: the
    /// first-winning value can change even when its deduplicated ID sequence does not.
    let containedDuplicateIDs: Bool
    @Binding var selection: Set<Item.ID>
    let rowContent: (Item) -> AnyView
    var configuration = FastListConfiguration<Item>()

    // MARK: Initializers

    /// Creates a list with a multiple-selection binding.
    ///
    /// - Parameters:
    ///   - items: The rows to display, already filtered and sorted. If IDs repeat, the
    ///     first item for each ID is displayed and later duplicates are ignored.
    ///   - selection: A binding to the set of selected row ids.
    ///   - row: Builds the SwiftUI content for a row. Make the non-interactive parts
    ///     hit-transparent (see the type's discussion).
    public init(
        _ items: [Item],
        selection: Binding<Set<Item.ID>>,
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        let deduplicatedItems = deduplicatedFastListItems(items)
        self.items = deduplicatedItems
        containedDuplicateIDs = deduplicatedItems.count != items.count
        _selection = selection
        rowContent = { AnyView(row($0)) }
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

    /// Rebuilds visible row content when `id` changes, even if the item id sequence is
    /// unchanged.
    ///
    /// `FastList` normally avoids `reloadData` unless row ids change, so selection-only
    /// updates stay cheap. Use this when a row reads caller-owned state not captured by
    /// `items`, such as favorite ids or read/unread state. The value is an invalidation
    /// token, not row identity: change it only when those row-content inputs change.
    ///
    /// On macOS a changed value reloads the table's recycled rows. Native SwiftUI backends
    /// already reevaluate their row bodies and accept this modifier for source-compatible
    /// cross-platform list declarations.
    public func rowContentID(_ id: some Hashable) -> Self {
        copy { $0.rowContentID = AnyHashable(id) }
    }

    /// Rebuilds visible row content when `id` changes.
    ///
    /// Use ``rowContentID(_:)`` to make clear that this token invalidates hosted row
    /// content rather than controlling the identity of the list itself.
    @available(*, deprecated, renamed: "rowContentID(_:)")
    public func reloadID(_ id: some Hashable) -> Self {
        rowContentID(id)
    }

    /// Fires when the last visible row comes within `threshold` rows of the end of the data
    /// as a user scroll settles - the trigger for load-more / infinite-scroll paging.
    ///
    /// Unlike ``onTopRowChange(_:)``, this reflects the *bottom* of the viewport, so it fires
    /// correctly on any window size without estimating the visible-row count from row
    /// heights. A `threshold` of `0` fires only once the very last row is on screen; a larger
    /// threshold loads the next page before the user hits the bottom.
    ///
    /// ```swift
    /// .onReachEnd(threshold: 10) { loadNextPage() }
    /// ```
    ///
    /// Fires at most once per row count, so sitting at the bottom can't spin a paging loop
    /// while a page is in flight, and any page size re-arms it - including a page no larger
    /// than `threshold`, which leaves the viewport's bottom still inside the threshold zone.
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
    ///
    /// "Once" is enforced, so `then` is genuinely optional: a target left set across later
    /// updates - a persistently stored anchor, say - is not re-honored, and cannot pin the
    /// viewport. Setting the target back to `nil` and then to the same id again scrolls again.
    /// A target whose row isn't loaded yet stays pending until it appears.
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
        // Returns whether the press was consumed; `false` lets the table fall through to
        // `super.keyDown(with:)` so the responder chain still sees Return.
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.handleReturn() ?? false }

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
        // EVERY scroll - trackpad, mouse wheel, scrollbar, and keyboard - so onReachEnd (load-more)
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

        // Only reload when the row set actually changed (filter/sort/refresh) - never on a
        // bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(items, force: false)
        coordinator.applySelection(selection)

        // Honors the documented "scrolls a row into view *once*" contract: the coordinator
        // remembers the last id it scrolled to and declines repeats, so a caller who stores
        // the anchor persistently (and so never clears it via `then`) doesn't have every
        // later update - a selection change, a rowContentID bump - yank the viewport back.
        if coordinator.scrollToTargetIfNeeded(table) {
            DispatchQueue.main.async { configuration.onScrolledToID?() }
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
            // Note: no `selection:` binding on the `List`. A selection-bound `List` in a
            // `NavigationSplitView` content column draws the system's emphasized selection on
            // the focused cell - a saturated blue focus ring plus a vibrant text recolor that
            // is near-illegible over our own soft highlight, and which `.focusEffectDisabled()`
            // does not reach (it's the UIKit cell's selected+focused state, not a SwiftUI
            // focus effect). Instead each row drives the `selection` binding itself on tap and
            // we render the highlight entirely via `selectionBackground`, so the selected row
            // keeps normal, readable text and no ring.
            List {
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
            // sidebar, so we drive selection ourselves and draw our own inset,
            // rounded-rectangle highlight instead - no bleed, no clipping, no system emphasis.
            .listStyle(.plain)
            .onAppear(perform: reconcileSelection)
            .onChange(of: items.map(\.id)) { _, _ in reconcileSelection() }
        }

        private func reconcileSelection() {
            let reconciled = reconciledFastListSelection(selection, items: items)
            if reconciled != selection { selection = reconciled }
        }

        /// The per-row selection highlight: an inset, rounded-rectangle fill when the row
        /// is selected and clear otherwise. Drawn as the row background in place of any
        /// system selection (the `List` is unbound), keeping the highlight off the column's
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
            let isSelected = selection.contains(item.id)
            // Drive selection on tap rather than via a `List(selection:)` binding, so the
            // row shows our own highlight without the system's focused-cell ring / text
            // recolor (see `body`). A `.rect` content shape makes the whole row tappable
            // even where its content is hit-transparent; interactive controls inside the
            // row (e.g. a favorite-star button) still receive their own taps.
            #if os(tvOS)
            let base = rowContent(item)
                .contentShape(.rect)
                .onTapGesture {
                    selection = [item.id]
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .listRowBackground(selectionBackground(isSelected: isSelected))
            #else
            let base = rowContent(item)
                .contentShape(.rect)
                .onTapGesture {
                    selection = [item.id]
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .listRowBackground(selectionBackground(isSelected: isSelected))
                .swipeActions(edge: .leading) { swipeButtons(leading) }
                .swipeActions(edge: .trailing) { swipeButtons(trailing) }
            #endif

            // Only attach a context menu when one is configured, so unconfigured rows
            // don't long-press into an empty menu.
            Group {
                if menu.isEmpty {
                    base
                } else {
                    base.contextMenu { contextButtons(menu) }
                }
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
