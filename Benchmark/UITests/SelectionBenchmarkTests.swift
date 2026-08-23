import XCTest

/// Measures real, on-screen interactive selection latency: launches the host app, focuses the
/// list, and times a run of arrow-key selection moves. The same per-event overhead from the
/// XCUITest harness applies to both modes, so the difference between "list" and "fast" reflects
/// the app-side cost of updating selection over the complex rows.
final class SelectionBenchmarkTests: XCTestCase {
    private let moves = 12
    private let rows = "10000"
    private let trials = 2

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches `mode`, focuses the list, and returns seconds per selection move (median of
    /// `trials` runs).
    private func perMoveSeconds(mode: String) -> Double {
        var samples: [Double] = []
        for _ in 0..<trials {
            let app = XCUIApplication()
            app.launchEnvironment["BENCH_MODE"] = mode
            app.launchEnvironment["BENCH_ROWS"] = rows
            app.launch()

            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 20), "\(mode) window did not appear")
            // Focus the list by clicking a row near the top, then settle.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).click()
            for _ in 0..<5 { app.typeKey(.downArrow, modifierFlags: []) } // warm up

            let start = Date()
            for _ in 0..<moves { app.typeKey(.downArrow, modifierFlags: []) }
            samples.append(Date().timeIntervalSince(start) / Double(moves))

            app.terminate()
        }
        return samples.sorted()[samples.count / 2]
    }

    func testSelectionLatencyListVsFastList() {
        let list = perMoveSeconds(mode: "list")
        let fast = perMoveSeconds(mode: "fast")
        let ms = { (seconds: Double) in String(format: "%.1f ms", seconds * 1000) }

        print("""

        SELECTION LATENCY (\(rows) complex rows, per arrow-key move, median of \(trials))
        --------------------------------------------------------------
        SwiftUI List : \(ms(list))
        FastList     : \(ms(fast))
        speedup      : \(String(format: "%.2fx", list / fast))
        --------------------------------------------------------------
        """)
    }
}
