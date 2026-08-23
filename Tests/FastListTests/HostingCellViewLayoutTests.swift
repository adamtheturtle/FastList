#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FastList

@MainActor
@Suite struct HostingCellViewLayoutTests {
    @Test func defersHeightNotificationsUntilAfterLayout() {
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))

        var heightNotes = 0
        var inLayout = false
        var calledDuringLayout = false
        let cell = HostingCellView(identifier: .fastListCell)
        cell.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        cell.rowIndex = 0
        cell.enclosingTableView = table
        cell.onHeightChange = {
            if inLayout { calledDuringLayout = true }
            heightNotes += 1
        }

        cell.host(AnyView(Text("Short")))
        inLayout = true
        cell.layout()
        inLayout = false
        #expect(heightNotes == 0)

        cell.host(AnyView(VStack { Text("Taller"); Text("Second line") }))
        cell.layout()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(heightNotes >= 2)
        #expect(!calledDuringLayout)
    }
}
#endif
