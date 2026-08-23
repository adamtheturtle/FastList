# ``FastList``

@Metadata {
    @DisplayName("FastList")
}

FastList owns native list mechanics: recycled rows, selection, activation, native action
and menu rendering, row dragging, paging signals, and scroll-position reporting. Calling
apps own row layout and the domain meaning of actions, menus, drags, pages, and persisted
scroll state.

``SwipeAction`` and ``MenuItem`` are platform-neutral inputs to the native renderers, not
an app design system.

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
- ``FastList/FastList/onReachEnd(threshold:perform:)``
- ``FastList/FastList/scrollToRow(id:then:)``

### Invalidating row content

- ``FastList/FastList/rowContentID(_:)``

### Guides

- <doc:PlatformFeatureMatrix>
- <doc:HitTesting>
- <doc:FilterPerformance>
- <doc:ThreadingAndSIL>
