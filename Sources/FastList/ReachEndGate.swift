//
//  ReachEndGate.swift
//  FastList
//

/// Shared paging de-duplication for the AppKit and native SwiftUI backends.
struct FastListReachEndGate {
    private var firedAtCount: Int?

    mutating func consume(lastVisibleRow: Int, itemCount: Int, threshold: Int) -> Bool {
        guard (0 ..< itemCount).contains(lastVisibleRow),
              lastVisibleRow >= itemCount - 1 - threshold,
              firedAtCount != itemCount else { return false }

        firedAtCount = itemCount
        return true
    }

    mutating func reset() {
        firedAtCount = nil
    }
}
