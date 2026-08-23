import Testing
@testable import FastList

@Suite struct FastListIDDiffTests {
    @Test func detectsInsertionsAndDeletions() {
        let diff = FastListIDDiff.difference(from: [1, 2, 3], to: [2, 3, 4])
        #expect(Array(diff.deletions) == [0])
        #expect(Array(diff.insertions) == [2])
        #expect(diff.isOrderPreserving)
        #expect(diff.supportsIncrementalUpdate)
    }

    @Test func flagsReordersAsNonIncremental() {
        let diff = FastListIDDiff.difference(from: [1, 2, 3], to: [3, 2, 1])
        #expect(diff.deletions.isEmpty)
        #expect(diff.insertions.isEmpty)
        #expect(!diff.isOrderPreserving)
        #expect(!diff.supportsIncrementalUpdate)
    }

    @Test func identicalSnapshotsAreNotIncremental() {
        let diff = FastListIDDiff.difference(from: [1, 2], to: [1, 2])
        #expect(!diff.supportsIncrementalUpdate)
    }
}
