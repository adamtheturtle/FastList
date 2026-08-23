//
//  Configuration.swift
//  FastList
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// How many rows a ``FastList`` lets the user select.
///
/// Chosen by the initializer the caller uses rather than by a modifier, so the table's
/// AppKit selection behavior always matches the shape of the binding that drives it.
public enum FastListSelectionMode: Sendable {
    /// No selection at all: the table is not selectable, so a click can't leave a
    /// highlight behind. Used by the `init(_:row:)` initializer, which has no binding.
    case none
    /// Exactly one row at a time. Used by the `Binding<Item.ID?>` initializer, whose
    /// binding cannot represent more than one selected row.
    case single
    /// Any number of rows. Used by the `Binding<Set<Item.ID>>` initializer.
    case multiple
}

/// The platform-neutral role of a list action.
///
/// `FastList` owns translating the role into native AppKit or SwiftUI presentation. The
/// calling app owns the action's domain meaning and decides when an action is destructive.
public enum FastListActionRole: Sendable {
    /// A standard action (grey background unless a ``SwipeAction/tint`` is given).
    case normal
    /// A destructive action (red background, leftmost on a trailing swipe).
    case destructive
}

/// A platform-neutral description of one swipe action.
///
/// `FastList` renders this value as an `NSTableViewRowAction` on macOS and a SwiftUI swipe
/// button on supported non-macOS platforms. The calling app owns the title, styling, and
/// domain operation; this type is only the transport value between that app code and the
/// native list renderer.
public struct SwipeAction {
    /// The action's title. Always set so VoiceOver announces it, even when a
    /// ``systemImage`` replaces the visible text.
    public var title: String
    /// Whether this is a standard or destructive action.
    public var role: FastListActionRole
    /// The revealed button's background color. `nil` uses the system default (grey for
    /// `.normal`, red for `.destructive`).
    public var tint: Color?
    /// An SF Symbol shown instead of the title - the standard macOS swipe look.
    /// `NSTableViewRowAction` renders an image *or* a title, never both, so when this is
    /// set the title is used only for accessibility.
    public var systemImage: String?
    /// Performed when the user taps the revealed button.
    public var action: () -> Void

    public init(
        title: String,
        role: FastListActionRole = .normal,
        tint: Color? = nil,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.tint = tint
        self.systemImage = systemImage
        self.action = action
    }
}

/// A platform-neutral description of one entry in a row's context menu.
///
/// `FastList` renders this value as a native `NSMenuItem` on macOS and as SwiftUI menu
/// content on supported non-macOS platforms. Menu construction and command semantics stay
/// in the calling app; this type only carries their native-rendering inputs.
public enum MenuItem {
    /// A clickable menu entry.
    case button(
        title: String,
        isEnabled: Bool = true,
        role: FastListActionRole = .normal,
        action: () -> Void
    )
    /// A separator line between groups of buttons.
    case separator
}

/// The optional behaviors layered onto a ``FastList`` by its modifiers. Internal; callers
/// configure it through the fluent modifier methods on ``FastList``.
struct FastListConfiguration<Item: Identifiable> {
    /// How many rows the user may select. Set by the initializer, not by a modifier: it is a
    /// property of the binding's shape, so it can't be changed independently of it.
    var selectionMode: FastListSelectionMode = .multiple
    var onDoubleClick: ((Item) -> Void)?
    var onReturnKey: ((Item) -> Void)?
    var leadingSwipe: ((Item) -> [SwipeAction])?
    var trailingSwipe: ((Item) -> [SwipeAction])?
    var contextMenu: ((Item, Set<Item.ID>) -> [MenuItem])?
    // The drag payload/session callbacks are typed in AppKit (NSPasteboardItem /
    // NSDraggingSession), so they exist only on macOS.
    #if os(macOS)
        var pasteboardItem: ((Item) -> NSPasteboardItem?)?
        var onDragSessionBegan: ((NSDraggingSession) -> Void)?
    #endif
    var onDragSessionEnded: (() -> Void)?
    var onTopRowChange: ((Item.ID?) -> Void)?
    /// Fired when the last visible row comes within `reachEndThreshold` rows of the end, the
    /// signal for load-more paging. Kept separate from `onTopRowChange` because the bottom of
    /// the viewport, not the top, is what tells a pager it's near the end.
    var onReachEnd: (() -> Void)?
    /// How many rows from the end the last visible row must reach before `onReachEnd` fires.
    var reachEndThreshold = 0
    var scrollToID: Item.ID?
    var onScrolledToID: (() -> Void)?
    /// Rebuilds rows when caller-controlled row-content inputs change even if row ids did
    /// not. Selection-only updates still reuse the existing table rows.
    var rowContentID: AnyHashable?
    var accessibilityIncludesRowPosition = false
    var accessibilityAnnouncesSelectionChanges = false
    var highlightsRowsOnHover = false
    /// Shown instead of the list when `items` is empty.
    var emptyStateContent: (() -> AnyView)?
    var listHeaderContent: (() -> AnyView)?
    var listFooterContent: (() -> AnyView)?
    /// Loads rows ahead of the visible viewport. Fires with upcoming items when the last
    /// visible row nears the prefetch window.
    var onPrefetchRows: (([Item]) -> Void)?
    /// How many rows beyond the last visible index to include in a prefetch callback.
    var prefetchRowCount = 10
}
