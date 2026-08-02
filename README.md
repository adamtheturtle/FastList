# FastList

A drop-in, `NSTableView`-backed replacement for SwiftUI `List` on macOS.

[Documentation](https://swiftpackageindex.com/adamtheturtle/FastList/documentation/fastlist) |
[Swift Package Index](https://swiftpackageindex.com/adamtheturtle/FastList)

## Installation

```swift
.package(url: "https://github.com/adamtheturtle/FastList.git", from: "0.5.0")
```

Add the `FastList` product to your target dependencies.

## Scope

`FastList` owns native list mechanics: recycled macOS rows, selection, activation,
swipe and context-menu rendering, row dragging, paging signals, and scroll-position
reporting/restoration. Its native SwiftUI backend supplies the same shared list behavior
to supported non-macOS callers.

Calling apps own row layout, domain commands, menu construction, drag payload meaning,
pagination state and UI, and persisted scroll state. `SwipeAction` and `MenuItem` are small
platform-neutral inputs to FastList's native renderers; they are not a shared design system.

When hosted row content depends on caller-owned state that is not represented by the item
ids, use `rowContentID(_:)` with a revision or other inexpensive `Hashable` token. Changing
the token rebuilds recycled macOS rows without turning ordinary selection updates into full
reloads.

The `FastListDemo` executable is the compile-checked usage example:

```sh
swift run FastListDemo
```

## Requirements

- Swift 5.9+
- macOS 13+ or iOS 17+

## License

MIT. See [LICENSE](LICENSE).
