//
//  FastListAnimatedDiff.swift
//  FastList
//

import Foundation

/// Ordered-identity diff used to choose animated insert/delete vs full reload.
struct FastListAnimatedDiff {
    var deletions: IndexSet
    var insertions: IndexSet
    var isOrderPreserving: Bool
    var hasSharedIdentities: Bool

    static func difference<ID: Hashable>(from oldIDs: [ID], to newIDs: [ID]) -> FastListAnimatedDiff {
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

        return FastListAnimatedDiff(
            deletions: deletions,
            insertions: insertions,
            isOrderPreserving: oldShared == newShared,
            hasSharedIdentities: !oldShared.isEmpty
        )
    }

    var supportsIncrementalUpdate: Bool {
        // Full identity replacement (no shared ids) keeps using `reloadData`, which is what
        // callers expect when the snapshot is swapped rather than patched.
        isOrderPreserving
            && hasSharedIdentities
            && !(deletions.isEmpty && insertions.isEmpty)
    }
}
