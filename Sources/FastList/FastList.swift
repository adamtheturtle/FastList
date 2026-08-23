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
    #if !os(macOS)
        @State private var nativeReachEndGate = FastListReachEndGate()
        /// De-dupes `onTopRowChange` the same way the AppKit coordinator does.
        @State private var lastNativeTopRowID: Item.ID?
        /// Honors ``scrollToRow(id:then:)`` once until the target is cleared, matching macOS.
        @State private var lastHonoredScrollToID: Item.ID?
    #endif

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

    /// Creates a list with a single-selection binding.
    ///
    /// The table is put into single-selection mode, so the user cannot shift- or
    /// command-click a second row: a multi-row selection that this binding could not
    /// represent is never formed in the first place. (Collapsing one after the fact with
    /// `Set.first` would pick an arbitrary, hash-order-dependent row.)
    public init(
        _ items: [Item],
        selection: Binding<Item.ID?>,
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        self.init(
            items,
            selection: Binding(
                get: { selection.wrappedValue.map { [$0] } ?? [] },
                // The table is single-selection, so this set holds at most one id.
                set: { selection.wrappedValue = $0.first }
            ),
            row: row
        )
        configuration.selectionMode = .single
    }

    /// Creates a non-selectable list.
    ///
    /// The table itself is made non-selectable, rather than merely dropping the selection
    /// on the floor: a click leaves no highlight to begin with. A discarding binding would
    /// let AppKit highlight the clicked row and, because a write that changes nothing
    /// invalidates nothing, never get a chance to undo it.
    public init(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View
    ) {
        self.init(items, selection: .constant([]), row: row)
        configuration.selectionMode = .none
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

    /// Adds a native right-click menu to every row. The closure receives the clicked row and
    /// the current selection set so you can build single-row or multi-selection menus.
    ///
    /// ```swift
    /// .rowContextMenu { row, selection in
    ///     [.button(title: "Open") { open(row) },
    ///      .button(title: "Delete \(selection.count)", isEnabled: !selection.isEmpty) { delete(selection) }]
    /// }
    /// ```
    public func rowContextMenu(_ items: @escaping (Item, Set<Item.ID>) -> [MenuItem]) -> Self {
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

    /// Adds an accessibility value such as "3 of 100" to each row.
    public func accessibilityRowPosition(_ enabled: Bool = true) -> Self {
        copy { $0.accessibilityIncludesRowPosition = enabled }
    }

    /// Posts an accessibility announcement when the selection set changes.
    public func accessibilityAnnounceSelectionChanges(_ enabled: Bool = true) -> Self {
        copy { $0.accessibilityAnnouncesSelectionChanges = enabled }
    }

    /// Highlights the row under the pointer on macOS.
    public func hoverHighlight(_ enabled: Bool = true) -> Self {
        copy { $0.highlightsRowsOnHover = enabled }
    }

    /// Pins a header view above the list rows.
    public func listHeader<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        copy { $0.listHeaderContent = { AnyView(content()) } }
    }

    /// Pins a footer view below the list rows.
    public func listFooter<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        copy { $0.listFooterContent = { AnyView(content()) } }
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

    /// Shows `content` when the list has no rows instead of an empty table or list.
    ///
    /// ```swift
    /// .emptyState {
    ///     ContentUnavailableView("No results", systemImage: "magnifyingglass")
    /// }
    /// ```
    public func emptyState<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        copy { $0.emptyStateContent = { AnyView(content()) } }
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

    public func makeNSView(context: Context) -> FastListContainerView {
        let table = KeyHandlingTableView()
        table.headerView = nil
        table.style = .inset
        table.usesAutomaticRowHeights = true
        configureSelection(for: table)
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
        table.onHoveredRowChanged = { [weak coordinator = context.coordinator, weak table] row in
            guard let coordinator, let table else { return }
            coordinator.updateHoveredRow(row, in: table)
        }
        table.onSelectAll = { [weak coordinator = context.coordinator] in coordinator?.handleSelectAll() ?? false }

        // Drive the right-click menu
        // lazily in `menuNeedsUpdate`) rather than overriding `menu(for:)`, so AppKit's
        // native contextual-menu machinery runs and draws the focus-ring outline around a
        // right-clicked row that isn't selected. Only install it when a menu is configured,
        // so right-clicking an unconfigured list shows nothing.
        context.coordinator.updateContextMenuRegistration(on: table)

        context.coordinator.updateDragRegistration(on: table)

        context.coordinator.tableView = table
        context.coordinator.reloadIfNeeded(items, force: true)

        let container = FastListContainerView(frame: .zero)
        container.scrollView.documentView = table
        container.scrollView.hasVerticalScroller = true
        container.scrollView.drawsBackground = false
        context.coordinator.containerView = container
        // Track every bounds change (wheel, scrollbar, keyboard, and trackpad) plus the final
        // settled position after live scrolling. The coordinator owns the observer lifecycle so
        // SwiftUI dismantling can explicitly remove both registrations.
        context.coordinator.installScrollObservers(for: container.scrollView)
        return container
    }

    public static func dismantleNSView(_ container: FastListContainerView, coordinator: Coordinator) {
        coordinator.removeScrollObservers()
        coordinator.tableView = nil
        coordinator.containerView = nil
        container.scrollView.documentView = nil
    }

    public func updateNSView(_ container: FastListContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.tableView else { return }
        configureSelection(for: table)
        coordinator.updateContextMenuRegistration(on: table)
        coordinator.updateDragRegistration(on: table)

        // Only reload when the row set actually changed (filter/sort/refresh) - never on a
        // bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(items, force: false)
        coordinator.applySelection(selection)

        container.updateChrome(
            header: configuration.listHeaderContent?(),
            footer: configuration.listFooterContent?()
        )
        let showsEmpty = items.isEmpty && configuration.emptyStateContent != nil
        container.updateEmptyState(configuration.emptyStateContent?(), isVisible: showsEmpty)

        // Honors the documented "scrolls a row into view *once*" contract: the coordinator
        // remembers the last id it scrolled to and declines repeats, so a caller who stores
        // the anchor persistently (and so never clears it via `then`) doesn't have every
        // later update - a selection change, a rowContentID bump - yank the viewport back.
        if coordinator.scrollToTargetIfNeeded(table) {
            DispatchQueue.main.async { configuration.onScrolledToID?() }
        }
    }

    /// Matches the table's AppKit selection behavior to the initializer the caller used.
    ///
    /// `.single` blocks shift/command-click, so a multi-row selection - which a
    /// `Binding<Item.ID?>` cannot represent - is impossible to form in the first place.
    /// `.none` additionally refuses selection outright via the coordinator's
    /// `selectionShouldChange(in:)` / `tableView(_:shouldSelectRow:)`, so a click leaves no
    /// highlight at all. (`NSTableView` has no `isSelectable`; the delegate is the supported
    /// way to make a table non-selectable, and unlike `allowsEmptySelection` juggling it also
    /// covers Select All and keyboard navigation.)
    func configureSelection(for table: NSTableView) {
        table.allowsMultipleSelection = configuration.selectionMode == .multiple
    }

    #endif
}

#if os(macOS)
    extension FastList: NSViewRepresentable {}
#else
    // MARK: View (iOS / iPadOS)

    /// Vertical origin of each visible row in the list coordinate space. Used to pick the
    /// topmost on-screen row for ``onTopRowChange``.
    private enum NativeVisibleRowMinYKey: PreferenceKey {
        static var defaultValue: [Int: CGFloat] { [:] }

        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    /// The iPad backend: a native SwiftUI `List`. SwiftUI's `List` is `UITableView`-backed
    /// and recycles rows, so the large-list selection cost that motivated the AppKit
    /// `NSTableView` path on macOS isn't a problem here - the platform list is already
    /// fast. Selection (driving a `NavigationSplitView` detail), per-row swipe actions, and
    /// the per-row context menu map straight onto the same `FastList` configuration.
    /// Scroll restore (`onTopRowChange` / `scrollToRow`), pointer double-tap, and hardware
    /// Return share the same modifiers as the macOS backend.
    extension FastList: View {
        public var body: some View {
            VStack(spacing: 0) {
                if let listHeaderContent = configuration.listHeaderContent {
                    listHeaderContent()
                }
                Group {
                    if items.isEmpty, let emptyStateContent = configuration.emptyStateContent {
                        emptyStateContent()
                    } else {
                        nativeListBody
                    }
                }
                if let listFooterContent = configuration.listFooterContent {
                    listFooterContent()
                }
            }
        }

        @ViewBuilder
        private var nativeListBody: some View {
            // Note: no `selection:` binding on the `List`. A selection-bound `List` in a
            // `NavigationSplitView` content column draws the system's emphasized selection on
            // the focused cell - a saturated blue focus ring plus a vibrant text recolor that
            // is near-illegible over our own soft highlight, and which `.focusEffectDisabled()`
            // does not reach (it's the UIKit cell's selected+focused state, not a SwiftUI
            // focus effect). Instead each row drives the `selection` binding itself on tap and
            // we render the highlight entirely via `selectionBackground`, so the selected row
            // keeps normal, readable text and no ring.
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { indexedItem in
                        row(for: indexedItem.element, at: indexedItem.offset)
                            .id(indexedItem.element.id)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: NativeVisibleRowMinYKey.self,
                                        value: [
                                            indexedItem.offset: geometry.frame(in: .named("fastListNative")).minY
                                        ]
                                    )
                                }
                            }
                            .onAppear {
                                consumeNativeReachEnd(lastVisibleRow: indexedItem.offset)
                            }
                            .onChange(of: items.count) { _, _ in
                                // A page no larger than the threshold can leave an already-visible
                                // row inside the new threshold zone. Re-evaluate visible rows when
                                // the count changes instead of waiting for another scroll gesture.
                                consumeNativeReachEnd(lastVisibleRow: indexedItem.offset)
                            }
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
                .coordinateSpace(name: "fastListNative")
                .onPreferenceChange(NativeVisibleRowMinYKey.self, perform: reportNativeTopRow(from:))
                .onAppear {
                    reconcileSelection()
                    honorNativeScrollToIfNeeded(proxy: proxy)
                }
                .onChange(of: items.map(\.id)) { _, _ in
                    reconcileSelection()
                    honorNativeScrollToIfNeeded(proxy: proxy)
                    if items.isEmpty {
                        reportNativeTopRowID(nil)
                    }
                }
                .onChange(of: configuration.scrollToID) { _, _ in
                    honorNativeScrollToIfNeeded(proxy: proxy)
                }
                .onChange(of: configuration.onReachEnd == nil) { _, isDisabled in
                    if isDisabled { nativeReachEndGate.reset() }
                }
                .focusable(configuration.onReturnKey != nil)
                .onKeyPress(.return) {
                    handleNativeReturnKey()
                }
                .onChange(of: selection) { _, newValue in
                    announceNativeSelectionChange(count: newValue.count)
                }
            }
        }

        private func announceNativeSelectionChange(count: Int) {
            guard configuration.accessibilityAnnouncesSelectionChanges else { return }
            let message = count == 1 ? "1 row selected" : "\(count) rows selected"
            AccessibilityNotification.Announcement(message).post()
        }

        private func consumeNativeReachEnd(lastVisibleRow: Int) {
            guard let onReachEnd = configuration.onReachEnd else { return }

            var gate = nativeReachEndGate
            guard gate.consume(
                lastVisibleRow: lastVisibleRow,
                itemCount: items.count,
                threshold: configuration.reachEndThreshold
            ) else { return }

            nativeReachEndGate = gate
            onReachEnd()
        }

        private func handleNativeRowTap(_ item: Item) {
            guard configuration.selectionMode != .none else { return }
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                if selection.contains(item.id) {
                    selection.remove(item.id)
                } else {
                    selection.insert(item.id)
                }
                return
            }
            #endif
            selection = [item.id]
        }

        private func reconcileSelection() {
            let reconciled = reconciledFastListSelection(selection, items: items)
            if reconciled != selection { selection = reconciled }
        }

        /// Picks the topmost row whose frame intersects the list viewport (minY closest to
        /// zero without being far above the clip), matching AppKit's visible-rect top row.
        private func reportNativeTopRow(from minYs: [Int: CGFloat]) {
            guard configuration.onTopRowChange != nil else { return }
            guard !items.isEmpty else {
                reportNativeTopRowID(nil)
                return
            }

            let topOffset = minYs
                .filter { $0.value > -1 }
                .min(by: { $0.value < $1.value })?
                .key
            guard let topOffset, items.indices.contains(topOffset) else { return }

            reportNativeTopRowID(items[topOffset].id)
        }

        private func reportNativeTopRowID(_ id: Item.ID?) {
            guard id != lastNativeTopRowID else { return }
            lastNativeTopRowID = id
            configuration.onTopRowChange?(id)
        }

        private func honorNativeScrollToIfNeeded(proxy: ScrollViewProxy) {
            guard let id = configuration.scrollToID else {
                lastHonoredScrollToID = nil
                return
            }
            guard id != lastHonoredScrollToID,
                  items.contains(where: { $0.id == id }) else { return }

            lastHonoredScrollToID = id
            proxy.scrollTo(id, anchor: .top)
            configuration.onScrolledToID?()
        }

        @discardableResult
        private func handleNativeReturnKey() -> KeyPress.Result {
            guard let onReturnKey = configuration.onReturnKey,
                  let selectedID = selection.first,
                  let item = items.first(where: { $0.id == selectedID }) else {
                return .ignored
            }
            onReturnKey(item)
            return .handled
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
        private func row(for item: Item, at index: Int) -> some View {
            let leading = configuration.leadingSwipe?(item) ?? []
            let trailing = configuration.trailingSwipe?(item) ?? []
            let menu = configuration.contextMenu?(item, selection) ?? []
            let isSelected = selection.contains(item.id)
            let positioned = configuration.accessibilityIncludesRowPosition
                ? AnyView(rowContent(item).accessibilityValue("\(index + 1) of \(items.count)"))
                : rowContent(item)
            // Drive selection on tap rather than via a `List(selection:)` binding, so the
            // row shows our own highlight without the system's focused-cell ring / text
            // recolor (see `body`). A `.rect` content shape makes the whole row tappable
            // even where its content is hit-transparent; interactive controls inside the
            // row (e.g. a favorite-star button) still receive their own taps.
            // Double-tap opens via ``onDoubleClick`` (pointer / trackpad on iPad); single tap
            // still selects. Hardware Return is handled on the list itself.
            #if os(tvOS)
            let base = rowContent(item)
                .contentShape(.rect)
                .onTapGesture {
                    guard configuration.selectionMode != .none else { return }
                    selection = [item.id]
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .listRowBackground(selectionBackground(isSelected: isSelected))
            #else
            let base = positioned
                .contentShape(.rect)
                .onTapGesture(count: 2) {
                    configuration.onDoubleClick?(item)
                }
                .onTapGesture(count: 1) {
                    handleNativeRowTap(item)
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
