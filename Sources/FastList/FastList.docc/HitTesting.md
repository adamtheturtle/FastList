# Hit-testing with interactive controls

On macOS, each row hosts SwiftUI content inside an `NSHostingView`. Native table
selection, double-click, and context-menu hit testing belong to the
`NSTableView`, not to the hosted view tree.

## Make chrome hit-transparent

Apply `.allowsHitTesting(false)` to the non-interactive parts of the row so a
left click reaches the table underneath:

```swift
FastList(rows, selection: $selection) { row in
    HStack {
        Text(row.title)
        Spacer()
        Text(row.subtitle)
    }
    .allowsHitTesting(false)
}
```

Without that, the hosting view can swallow clicks and selection feels broken.

## Keep interactive controls hittable

Avoid disabling hit testing on controls that must receive events. Nest the
hit-transparent chrome around labels and leave buttons, toggles, and text fields
outside that modifier:

```swift
FastList(rows, selection: $selection) { row in
    HStack {
        VStack(alignment: .leading) {
            Text(row.title)
            Text(row.subtitle)
        }
        .allowsHitTesting(false)

        Spacer()

        Button {
            toggleFavorite(row)
        } label: {
            Image(systemName: row.isFavorite ? "star.fill" : "star")
        }
        .buttonStyle(.borderless)
    }
}
```

## iOS / iPadOS

The native SwiftUI `List` backend already uses a rectangular content shape and
per-row tap handling for selection. Prefer putting interactive controls in the
row body as usual; they keep their own gesture targets while the row chrome
remains tappable.
