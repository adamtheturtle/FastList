//
//  ReachEndGate.swift
//  FastList
//

/// Shared paging de-duplication for the AppKit and native SwiftUI backends.
///
/// Exposed under `@_spi(FastListTesting)` so host apps and package tests can assert
/// once-per-count paging without depending on private module details.
@_spi(FastListTesting)
public struct FastListReachEndGate {
    private var firedAtCount: Int?

    public init() {}

    public mutating func consume(lastVisibleRow: Int, itemCount: Int, threshold: Int) -> Bool {
        guard (0 ..< itemCount).contains(lastVisibleRow),
              lastVisibleRow >= itemCount - 1 - threshold,
              firedAtCount != itemCount else { return false }

        firedAtCount = itemCount
        return true
    }

    public mutating func reset() {
        firedAtCount = nil
    }
}
