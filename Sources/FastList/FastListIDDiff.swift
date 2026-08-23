//
//  FastListIDDiff.swift
//  FastList
//
//  Ordered-identity diff used as a stepping-stone toward a full
//  `NSTableViewDiffableDataSource` migration. Callers (and animated reload
//  paths) can apply inserts/deletes without a wholesale `reloadData`.
//

import Foundation

/// The ordered identity changes between two row-id snapshots.
public struct FastListIDDiff<ID: Hashable>: Sendable {
    /// Indexes to remove from the old snapshot, relative to the old ordering.
    public var deletions: IndexSet
    /// Indexes to insert into the new snapshot, relative to the new ordering.
    public var insertions: IndexSet
    /// Whether every surviving id kept its relative order (no moves).
    public var isOrderPreserving: Bool
    public var hasSharedIdentities: Bool

    public init(
        deletions: IndexSet,
        insertions: IndexSet,
        isOrderPreserving: Bool,
        hasSharedIdentities: Bool
    ) {
        self.deletions = deletions
        self.insertions = insertions
        self.isOrderPreserving = isOrderPreserving
        self.hasSharedIdentities = hasSharedIdentities
    }

    /// Diffs `oldIDs` into `newIDs` using set membership.
    ///
    /// Moves are not expanded into discrete operations: when relative order of
    /// shared ids changes, `isOrderPreserving` is `false` so callers can fall
    /// back to a full reload.
    public static func difference(from oldIDs: [ID], to newIDs: [ID]) -> FastListIDDiff<ID> {
        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)

        var deletions = IndexSet()
        for (index, id) in oldIDs.enumerated() where !newSet.contains(id) {
            deletions.insert(index)
        }

        var insertions = IndexSet()
        for (index, id) in newIDs.enumerated() where !oldSet.contains(id) {
            insertions.insert(index)
        }

        let oldShared = oldIDs.filter(newSet.contains)
        let newShared = newIDs.filter(oldSet.contains)
        let isOrderPreserving = oldShared == newShared

        return FastListIDDiff(
            deletions: deletions,
            insertions: insertions,
            isOrderPreserving: isOrderPreserving,
            hasSharedIdentities: !oldShared.isEmpty
        )
    }

    /// Whether this diff can be applied as animated insert/delete without a full reload.
    public var supportsIncrementalUpdate: Bool {
        isOrderPreserving
            && hasSharedIdentities
            && !(deletions.isEmpty && insertions.isEmpty)
    }
}
