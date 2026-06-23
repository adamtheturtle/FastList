# FastList

A drop-in replacement for SwiftUI's `List` on **macOS**, backed by `NSTableView`.

SwiftUI's `List` and `Table` rebuild every visible row's body on each selection change and
stall badly on large data sets — selecting a row in a list of a few thousand items can hang
for seconds. `FastList` instead materializes and recycles only the **visible** rows, the way
Mail's message list works, so selection and scrolling stay instant no matter how long the
list is — while keeping a SwiftUI-first, declarative API.

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

## Why this exists

macOS `List`/`Table` performance degrades sharply at scale (documented hangs of several
seconds selecting a row in a ~1k-row table; effectively unusable past tens of thousands of
rows). macOS, unlike iOS, wants to know every row's size and historically didn't lazily load
rows or recycle cells the way `NSTableView` does. The community work-around has been to drop
down to AppKit and hand-roll an `NSViewRepresentable` per app.

`FastList` is that bridge, packaged and maintained — with the interaction features the
hand-rolled versions usually skip.

### Compared to the alternatives

| | `List` / `Table` (native) | AppKit, hand-rolled | **FastList** |
|---|---|---|---|
| Performance on 10k+ rows | Poor | Good | **Good** |
| SwiftUI cell content | n/a (is SwiftUI) | via `NSHostingView` | **via `NSHostingView`** |
| SwiftUI-first declarative API | Yes | No | **Yes** |
| Selection binding | Yes | DIY | **Yes (single & multi)** |
| Double-click | Awkward | DIY | **Yes** |
| Return / Enter to open | No | DIY | **Yes** |
| Swipe actions | `List` only | DIY | **Yes (both edges, SF Symbols)** |
| Right-click menu | Yes | DIY | **Yes (native, focus ring)** |
| Drag & drop | Limited | DIY | **Yes (pasteboard payload + session hooks)** |
| Scroll-position restore | No | DIY | **Yes (`onTopRowChange` / `scrollToRow`)** |
| Automatic row heights | Yes (slow) | DIY | **Yes** |

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/adamtheturtle/FastList.git", from: "0.1.0")
```

```swift
.target(name: "App", dependencies: ["FastList"])
```

Requires **macOS 13+** and Swift 5.9+.

### Try the demo

```sh
swift run FastListDemo
```

Launches a window with 50,000 rows you can filter, multi-select, swipe, and open — instantly.
Or open `Package.swift` in Xcode and run the `FastListDemo` scheme.

API documentation lives in the bundled DocC catalog: in Xcode, **Product ▸ Build Documentation**.

## Usage

### Selection

```swift
// Multiple selection
FastList(rows, selection: $selectedIDs) { row in RowView(row) }      // Binding<Set<ID>>

// Single selection
FastList(rows, selection: $selectedID) { row in RowView(row) }       // Binding<ID?>

// No selection
FastList(rows) { row in RowView(row) }
```

`rows` is `[Item]` where `Item: Identifiable`. Filter and sort it yourself before handing it
over — `FastList` renders exactly what you pass.

### The hit-testing rule (important)

Each row hosts your SwiftUI view inside an `NSHostingView`. For the table's native click
selection to work, the **non-interactive** parts of the row must be hit-transparent — apply
`.allowsHitTesting(false)` to them so a left click falls through to the table. Genuinely
interactive controls inside the row (a `Toggle`, a favorite star `Button`) keep working
normally; just don't make the whole row swallow clicks.

### Swipe actions

```swift
.swipeActions(edge: .leading) { row in
    [SwipeAction(title: "Flag", tint: .yellow, systemImage: "flag.fill") { flag(row) }]
}
.swipeActions(edge: .trailing) { row in
    [SwipeAction(title: "Delete", role: .destructive, systemImage: "trash") { delete(row) }]
}
```

`NSTableViewRowAction` renders an image **or** a title, never both — when you set
`systemImage`, the `title` is used for VoiceOver only.

### Right-click menu

```swift
.rowContextMenu { row in
    [.button(title: "Open") { open(row) },
     .separator,
     .button(title: "Delete", isEnabled: row.isDeletable) { delete(row) }]
}
```

The closure runs per right-clicked row, so you can build single-row vs. multi-selection
menus by reading your own selection state.

### Drag & drop

```swift
.onRowDrag { row in
    let item = NSPasteboardItem()
    item.setString(row.url.absoluteString, forType: .URL)
    return item            // return nil to make a row non-draggable
}
.onDragSession(began: { session in revealDropZoneIfNeeded(session) },
               ended: { hideDropZone() })
```

The pasteboard payload is built at the AppKit layer (the hosted SwiftUI content is
hit-transparent, which disables a SwiftUI `.draggable`). The session hooks let the host
inspect the drag and react without leaking app-specific pasteboard types into the list.

### Scroll-position restore

```swift
.onTopRowChange { topID in defaults.scrollAnchor = topID }   // persist as the user scrolls
.scrollToRow(id: restoredAnchor) { restoredAnchor = nil }    // restore once on launch
```

## How it works

- One `NSTableColumn`, header hidden, `usesAutomaticRowHeights` on — so it behaves like a
  single-column `List` with variable-height rows.
- Rows are recycled `NSTableCellView`s, each hosting your SwiftUI view in an `NSHostingView`
  sized to its intrinsic content height.
- The coordinator keeps an `id → row` index so selection and `scrollToRow` are O(1), and a
  re-entrancy guard stops the SwiftUI binding and the table's selection from ping-ponging.
- `reloadData` only runs when the **row set** changes (filter / sort / refresh), never on a
  bare selection change — which is the whole point.

## Requirements & caveats

- **macOS only.** This wraps AppKit; there is no iOS code path.
- Rows must be `Identifiable` with a `Hashable` id.
- Make non-interactive row content hit-transparent (see above).

## License

MIT — see [LICENSE](LICENSE).
