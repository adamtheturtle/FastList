# FastList

A drop-in replacement for SwiftUI's `List` on **macOS**, backed by `NSTableView`.

[**API documentation**](https://adamtheturtle.github.io/FastList/documentation/fastlist/)

![FastList demo showing 50,000 rows that scroll and select instantly](Resources/demo.png)

> The bundled `FastListDemo` showing 50,000 rows that filter, select, and scroll instantly.

SwiftUI's `List` and `Table` rebuild every visible row's body on each selection change and
slow down sharply on large data sets. Selecting a row in a list of a few thousand items can
hang for seconds. `FastList` instead materializes and recycles only the visible rows, the way
Mail's message list works, so selection and scrolling stay fast no matter how long the list
is, while keeping a SwiftUI-first, declarative API.

```swift
import FastList

FastList(people, selection: $selection) { person in
    PersonRow(person)
        .allowsHitTesting(false) // let clicks fall through to the table
}
.onDoubleClick { open($0) }
.onReturnKey { open($0) }
.swipeActions(edge: .trailing) { person in
    [SwipeAction(title: "Delete", role: .destructive, systemImage: "trash") { delete(person) }]
}
.rowContextMenu { person in
    [.button(title: "Copy Email") { copyEmail(person) },
     .separator,
     .button(title: "Delete") { delete(person) }]
}
```

Selection (single, multiple, or none), swipe actions, right-click menus, drag and drop, and
scroll-position restore are all covered in the
[API documentation](https://adamtheturtle.github.io/FastList/documentation/fastlist/).

## Benchmark

Selecting a row costs the same whether the list holds a thousand rows or a million, because
the table only ever renders the rows on screen. These figures measure FastList's own
per-update bookkeeping against a real `NSTableView`.

| Rows      | Selection change | Reindex on data change |
| --------- | ---------------- | ---------------------- |
| 1,000     | 3.6 µs           | 0.40 ms                |
| 10,000    | 3.5 µs           | 3.6 ms                 |
| 100,000   | 8.3 µs           | 64 ms                  |
| 1,000,000 | 3.5 µs           | 0.32 s                 |

"Selection change" is the work done when the selection moves from one row to another, which
stays flat as the list grows. "Reindex on data change" is the one-time cost of rebuilding the
id lookup when the filtered or sorted set changes, which scales with the row count. Measured
as the median of repeated runs on Apple Silicon with the Swift 6.3 toolchain; reproduce with:

```sh
FASTLIST_BENCHMARK=1 swift test --filter Benchmark
```

## Why this exists

macOS `List` and `Table` performance falls off at scale (reported hangs of several seconds
selecting a row in a list of about a thousand items, and unusable scrolling past tens of
thousands). macOS, unlike iOS, wants to know every row's size and historically did not lazily
load rows or recycle cells the way `NSTableView` does. The common workaround has been to drop
down to AppKit and hand-roll an `NSViewRepresentable` per app.

`FastList` is that bridge, packaged and maintained, with the interaction features the
hand-rolled versions usually skip.

|                              | `List` / `Table` (native) | AppKit, hand-rolled | FastList                          |
| ---------------------------- | ------------------------- | ------------------- | --------------------------------- |
| Performance on 10k+ rows     | Poor                      | Good                | Good                              |
| SwiftUI cell content         | n/a (is SwiftUI)          | via `NSHostingView` | via `NSHostingView`               |
| SwiftUI-first declarative API| Yes                       | No                  | Yes                               |
| Selection binding            | Yes                       | DIY                 | Yes (single and multi)            |
| Double-click                 | Awkward                   | DIY                 | Yes                               |
| Return / Enter to open       | No                        | DIY                 | Yes                               |
| Swipe actions                | `List` only               | DIY                 | Yes (both edges, SF Symbols)      |
| Right-click menu             | Yes                       | DIY                 | Yes (native, focus ring)          |
| Drag and drop                | Limited                   | DIY                 | Yes (pasteboard payload, session) |
| Scroll-position restore      | No                        | DIY                 | Yes                               |
| Automatic row heights        | Yes (slow)                | DIY                 | Yes                               |

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/adamtheturtle/FastList.git", from: "0.1.0")
```

```swift
.target(name: "App", dependencies: ["FastList"])
```

Requires **macOS 13+** and Swift 5.9+.

## Try the demo

```sh
swift run FastListDemo
```

Launches a window with 50,000 rows you can filter, multi-select, swipe, and open. Or open
`Package.swift` in Xcode and run the `FastListDemo` scheme.

## Hit-testing

Each row hosts your SwiftUI view inside an `NSHostingView`. For the table's native click
selection to work, the non-interactive parts of the row need to be hit-transparent: apply
`.allowsHitTesting(false)` to them so a left click falls through to the table. Interactive
controls inside the row (a `Toggle`, a favorite star `Button`) still receive their clicks.

## Requirements and caveats

- macOS only. This wraps AppKit; there is no iOS code path.
- Rows must be `Identifiable` with a `Hashable` id.
- Make non-interactive row content hit-transparent (see above).

## License

MIT. See [LICENSE](LICENSE).
