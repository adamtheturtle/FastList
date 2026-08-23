# Threading contract and SIL workaround

## Threading

All FastList AppKit work runs on the main actor. The `Coordinator` is marked
`@MainActor` and owns the `NSTableView` data source, delegate, menu, and scroll
observers. Call selection bindings, modifiers that mutate configuration, and
paging callbacks from the main actor as you would for any SwiftUI view update.

Do not call into the coordinator or table from a background queue. Snapshot
replacement (`reloadIfNeeded`) and scroll reporting assume main-thread AppKit
consistency.

## SIL optimizer workaround

Xcode's SIL optimizer (`EarlyPerfInliner`) has crashed while inlining the
generic `Coordinator` destructor during Release compilation. FastList keeps an
explicit `deinit` on `Coordinator` marked `@_optimize(none)` so member-wise
teardown still runs without hitting that compiler path.

Use the same opt-out in a host app only after you have reproduced a Release
compiler crash on a similar generic destructor. It is a narrow workaround, not
a general performance tip.
