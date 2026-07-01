//
//  Configuration.swift
//  FastList
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// The visual / behavioral role of a swipe action.
public enum FastListActionRole: Sendable {
    /// A standard action (grey background unless a ``SwipeAction/tint`` is given).
    case normal
    /// A destructive action (red background, leftmost on a trailing swipe).
    case destructive
}

/// One swipe action revealed on a row edge, rendered as an `NSTableViewRowAction` — the
/// same control Finder and Mail use for swipe-to-delete / swipe-to-flag.
public struct SwipeAction {
    /// The action's title. Always set so VoiceOver announces it, even when a
    /// ``systemImage`` replaces the visible text.
    public var title: String
    /// Whether this is a standard or destructive action.
    public var role: FastListActionRole
    /// The revealed button's background color. `nil` uses the system default (grey for
    /// `.normal`, red for `.destructive`).
    public var tint: Color?
    /// An SF Symbol shown instead of the title — the standard macOS swipe look.
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

/// One entry in a row's right-click menu. Rendered as a native `NSMenuItem`, because the
/// hosted SwiftUI row content is hit-transparent and so a SwiftUI `.contextMenu` on it
/// would never fire.
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
    var onDoubleClick: ((Item) -> Void)?
    var onReturnKey: ((Item) -> Void)?
    var leadingSwipe: ((Item) -> [SwipeAction])?
    var trailingSwipe: ((Item) -> [SwipeAction])?
    var contextMenu: ((Item) -> [MenuItem])?
    /// A cross-platform drag payload as a `URL` (e.g. a pad's web URL). On iOS it drives a
    /// native `.draggable` so a row can be dragged into Safari, Notes, or a Split View; on
    /// macOS the richer `pasteboardItem` path below is used instead.
    var dragURL: ((Item) -> URL?)?
    // The drag payload/session callbacks are typed in AppKit (NSPasteboardItem /
    // NSDraggingSession), so they exist only on macOS. iPad row dragging uses `dragURL`.
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
    /// Reloads rows when caller-controlled row-content inputs change even if row ids
    /// did not. Selection-only updates still reuse the existing table rows.
    var reloadID: AnyHashable?
    /// Fixed row height for the macOS backend. Nil keeps automatic row heights.
    var rowHeight: CGFloat?
}
