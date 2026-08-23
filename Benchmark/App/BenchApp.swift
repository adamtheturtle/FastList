import FastList
import SwiftUI

/// The benchmark host app. It renders either a SwiftUI `List` or a `FastList` of the same
/// complex rows, chosen by the `BENCH_MODE` environment variable ("list" or "fast"), with the
/// row count from `BENCH_ROWS`. The UI-test target launches it in each mode and times keyboard
/// selection. Both lists carry the accessibility identifier "benchList".
@main
struct BenchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 520, minHeight: 720)
        }
    }
}

struct RootView: View {
    @State private var items: [Item]
    @State private var selection: Set<Int> = []
    private let mode: String

    init() {
        let count = Int(ProcessInfo.processInfo.environment["BENCH_ROWS"] ?? "") ?? 10_000
        _items = State(initialValue: makeItems(count))
        mode = ProcessInfo.processInfo.environment["BENCH_MODE"] ?? "list"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(mode == "fast" ? "FastList" : "SwiftUI List") — \(items.count) rows")
                .font(.caption)
                .padding(4)
            Divider()
            if mode == "fast" {
                FastList(items, selection: $selection) { item in
                    ComplexRow(item: item).allowsHitTesting(false)
                }
                .accessibilityIdentifier("benchList")
            } else {
                List(items, selection: $selection) { item in
                    ComplexRow(item: item)
                }
                .accessibilityIdentifier("benchList")
            }
        }
    }
}
