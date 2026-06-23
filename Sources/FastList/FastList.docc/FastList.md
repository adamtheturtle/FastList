# ``FastList``

A drop-in replacement for SwiftUI's `List` on macOS, backed by `NSTableView`.

## Overview

SwiftUI's `List` and `Table` rebuild every visible row's body on each selection change and
slow down sharply on large data sets. Selecting a row in a list of a few thousand items can
hang for seconds. ``FastList/FastList`` instead materializes and recycles only the visible
rows, the way Mail's message list works, so selection and scrolling stay fast no matter how
long the list is, while keeping a SwiftUI-first, declarative API.

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

### Hit-testing

Each row hosts your SwiftUI view inside an `NSHostingView`. For the table's native click
selection to work, the non-interactive parts of the row need to be hit-transparent: apply
`.allowsHitTesting(false)` to them so a left click falls through to the table. Interactive
controls inside the row (a `Toggle`, a favorite star) still receive their clicks normally.

## Topics

### Creating a list

- ``FastList/FastList``

### Responding to activation

- ``FastList/FastList/onDoubleClick(_:)``
- ``FastList/FastList/onReturnKey(_:)``

### Row actions

- ``FastList/FastList/swipeActions(edge:_:)``
- ``SwipeAction``
- ``FastListActionRole``
- ``FastList/FastList/rowContextMenu(_:)``
- ``MenuItem``

### Drag and drop

- ``FastList/FastList/onRowDrag(_:)``
- ``FastList/FastList/onDragSession(began:ended:)``

### Scroll position

- ``FastList/FastList/onTopRowChange(_:)``
- ``FastList/FastList/scrollToRow(id:then:)``
