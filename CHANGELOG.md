# Changelog

This file records user-facing changes to FastList.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- macOS `.focusRing(_:)` to choose default, none, or exterior focus rings.
- iOS / iPadOS `.onRowDrag` using `NSItemProvider` and SwiftUI `.onDrag`.
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
