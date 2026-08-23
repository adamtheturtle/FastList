# Filter performance for 100k+ rows

FastList renders exactly the `[Item]` you pass. Filtering and sorting stay in
the calling app so the list never owns a second copy of your domain model.

## Keep filtering off the hot path

For lists of 100k+ rows:

1. Filter and sort on a background queue or with incremental indexing.
2. Publish a new array of visible items on the main actor when the query settles.
3. Hand that array to `FastList`. Identity changes trigger a native reload;
   selection-only updates do not.

```swift
FastList(visibleRows, selection: $selection) { row in
    RowView(row).allowsHitTesting(false)
}
.rowContentID(rowContentRevision)
```

## Prefer stable IDs

Stable `Identifiable` IDs let FastList rebuild its id-to-row index cheaply and
preserve selection across filter edits. Avoid regenerating IDs when only display
fields change.

## Use `rowContentID` for caller-owned state

When a row reads state that is not part of the item value (favorites, read
flags), bump `rowContentID` so recycled macOS cells refresh without treating a
selection change as a full data reload.

## Pair with paging when possible

If the full corpus is huge, prefer `onReachEnd` paging over loading every row
into the process at once. FastList's once-per-count gate is designed so small
page sizes still re-arm after each append.
