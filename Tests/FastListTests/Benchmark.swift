import AppKit
import SwiftUI
import Testing
@testable import FastList

//
// A microbenchmark of FastList's per-update bookkeeping. It is gated behind the
// FASTLIST_BENCHMARK environment variable so it does not run in normal test passes:
//
//   FASTLIST_BENCHMARK=1 swift test --filter Benchmark
//
// It measures the two operations FastList performs on its hot path against a real
// NSTableView: rebuilding the id index when the data set changes (O(rows)), and applying
// a selection change (independent of row count). NSTableView renders only visible rows, so
// these timings, not the row total, bound the work a selection or scroll triggers.
//

private struct BenchRow: Identifiable {
    let id: Int
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FASTLIST_BENCHMARK"] != nil))
struct Benchmark {
    private func median(_ values: [Duration]) -> Duration {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    @Test func selectionStaysFlatAsRowCountGrows() {
        let clock = ContinuousClock()
        print("\nFastList microbenchmark (median of repeated runs)")
        print(String(repeating: "-", count: 58))
        print("rows      reindex (data change)   selection change")

        for count in [1_000, 10_000, 100_000, 1_000_000] {
            let rows = (0..<count).map { BenchRow(id: $0) }
            let list = FastList(rows, selection: .constant([])) { Text(String($0.id)) }
            let coordinator = list.makeCoordinator()
            let table = NSTableView()
            table.addTableColumn(NSTableColumn(identifier: .fastListColumn))
            table.dataSource = coordinator
            table.delegate = coordinator
            coordinator.tableView = table

            // Reindex: the O(rows) work done once when the filtered/sorted set changes.
            var reindexSamples: [Duration] = []
            for _ in 0..<5 {
                reindexSamples.append(clock.measure { coordinator.reloadIfNeeded(rows, force: true) })
            }

            // Selection change: alternate between two single-row selections so each call
            // does real work rather than early-returning on an unchanged set.
            let iterations = 2_000
            let selectionTotal = clock.measure {
                for index in 0..<iterations {
                    coordinator.applySelection([index % 2])
                }
            }
            let perSelection = selectionTotal / iterations

            let rowsColumn = "\(count)".padding(toLength: 10, withPad: " ", startingAt: 0)
            let reindexColumn = describe(median(reindexSamples)).padding(toLength: 24, withPad: " ", startingAt: 0)
            print("\(rowsColumn)\(reindexColumn)\(describe(perSelection))")
        }
        print(String(repeating: "-", count: 58))
    }

    private func describe(_ duration: Duration) -> String {
        let nanos = Double(duration.components.attoseconds) / 1_000_000_000 + Double(duration.components.seconds) * 1_000_000_000
        if nanos >= 1_000_000 { return String(format: "%.2f ms", nanos / 1_000_000) }
        if nanos >= 1_000 { return String(format: "%.1f us", nanos / 1_000) }
        return String(format: "%.0f ns", nanos)
    }
}
