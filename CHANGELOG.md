# Changelog

This file records user-facing changes to FastList.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- macOS `.focusRing(_:)` to choose default, none, or exterior focus rings.
- iOS / iPadOS `.onRowDrag` using `NSItemProvider` and SwiftUI `.onDrag`.
- `.listStyle(_:)` for inset, plain, and sidebar chrome on macOS and iOS.
- `swipeActions(allowsFullSwipe:)` and coverage for more than two actions per edge.
- `FastListSection` and a sectioned initializer with SwiftUI `Section` headers on iOS.
- Animated insert/delete for in-order identity changes without a full `reloadData`.
- `FastListIDDiff` ordered-identity diff as a stepping-stone toward diffable data sources.
- `.onMove` row reordering on macOS (local drop) and iOS (`ForEach.onMove`).
- `.editing(_:)` to drive iOS `EditMode` for inline reorder/delete chrome.
- Demo pull-to-refresh via MacPullToRefresh.
- macOS `.onRowDrop` for drop destinations and row reorder targets.
- `.navigationSplitSelectionSync()` for `List(selection:)` sync in split views.
- Shared `FastListReachEndGate` for once-per-row-count paging on macOS and iOS.
- iOS / iPadOS `onReachEnd` wiring on the native SwiftUI `List` backend.
- Vale prose lint and Dependabot auto-merge for GitHub Actions.

### Changed

- Scroll observers are removed when the AppKit representable is dismantled.
- Top-row and reach-end callbacks ignore transient scroll notifications during snapshot reloads.
- Context menus and drag registration refresh when modifiers change after `makeNSView`.

### Fixed

- Selection bindings prune IDs that are no longer in the item snapshot.
- Duplicate item IDs keep the first-winning row only.
- `scrollToRow(id:then:)` honors a target once until cleared.
- Return without `onReturnKey` continues along the responder chain.

## [0.5.0]

- Initial public surface for the recycled-list primitive documented in the README and DocC catalog.
