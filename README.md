# FastList

A drop-in replacement for SwiftUI's `List` on **macOS**, backed by `NSTableView`. It
materializes and recycles only the visible rows, so selection and scrolling stay fast on lists
of any size, while keeping a SwiftUI-first, declarative API. SwiftUI's own `List` and `Table`
rebuild every visible row on each selection change and slow down sharply at a few thousand rows.

[**API documentation**](https://adamtheturtle.github.io/FastList/documentation/fastlist/)

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
```

Selection (single, multiple, or none), swipe actions, right-click menus, drag and drop, and
scroll-position restore are covered in the
[documentation](https://adamtheturtle.github.io/FastList/documentation/fastlist/).

## Benchmark

Selecting a row costs the same whether the list holds a thousand rows or a million, because the
table only renders the rows on screen. Measured against a real `NSTableView`:

| Rows      | Selection change | Reindex on data change |
| --------- | ---------------- | ---------------------- |
| 1,000     | 3.6 µs           | 0.40 ms                |
| 10,000    | 3.5 µs           | 3.6 ms                 |
| 100,000   | 8.3 µs           | 64 ms                  |
| 1,000,000 | 3.5 µs           | 0.32 s                 |

Selection change stays flat as the list grows; reindex is the one-time cost when the filtered
or sorted set changes. Reproduce with `FASTLIST_BENCHMARK=1 swift test --filter Benchmark`.

## Installation

```swift
.package(url: "https://github.com/adamtheturtle/FastList.git", from: "0.1.0")
```

Requires **macOS 13+** and Swift 5.9+. Run `swift run FastListDemo` for a 50,000-row demo.

## Hit-testing

Each row hosts your SwiftUI view in an `NSHostingView`. Apply `.allowsHitTesting(false)` to the
non-interactive parts of the row so left clicks fall through to the table for native selection;
interactive controls in the row (a `Toggle`, a `Button`) still receive their clicks.

## License

MIT. See [LICENSE](LICENSE).
