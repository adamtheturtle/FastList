# Platform feature matrix

FastList exposes one modifier surface. Behavior is implemented by the AppKit
`NSTableView` backend on macOS and by a native SwiftUI `List` on iOS and iPadOS.

| Capability | macOS | iOS / iPadOS |
| --- | --- | --- |
| Multi-selection binding | Yes | Yes (tap-driven highlight) |
| `navigationSplitSelectionSync` | Accepted | Yes (`List(selection:)`) |
| Swipe actions | Yes (`NSTableViewRowAction`) | Yes (SwiftUI swipe actions) |
| Context menu | Yes (native `NSMenu`) | Yes (SwiftUI context menu) |
| `onDoubleClick` | Yes | Yes (pointer double-tap) |
| `onReturnKey` | Yes | Yes (hardware keyboard) |
| `onRowDrag` / drag session | Yes (AppKit pasteboard) | Yes (`NSItemProvider` / `.onDrag`) |
| `onTopRowChange` | Yes (scroll bounds) | Yes (visible-row preference) |
| `scrollToRow(id:then:)` | Yes | Yes (`ScrollViewReader`) |
| `onReachEnd` | Yes | Yes (row `onAppear` + shared gate) |
| `rowContentID` | Reloads recycled cells | Accepted for source compatibility |
| `listStyle` | Yes (`NSTableView.Style`) | Yes (SwiftUI `ListStyle`) |

Prefer the shared modifiers so call sites stay cross-platform. Platform-only
APIs (`onRowDrag`, drag session observers) are compiled out of non-macOS builds.
