#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FastList

private struct Row: Identifiable {
    let id: Int
    let name: String
}

@MainActor
@Suite struct HostingCellViewLayoutTests {
    @Test func notesHeightWhenHostedContentGrows() {
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: .fastListColumn))

        var heightNotes = 0
        let cell = HostingCellView(identifier: .fastListCell)
        cell.rowIndex = 0
        cell.enclosingTableView = table
        cell.onHeightChange = { heightNotes += 1 }

        cell.host(AnyView(Text("Short")))
        cell.layout()

        cell.host(AnyView(VStack { Text("Taller"); Text("Second line") }))
        cell.layout()

        #expect(heightNotes >= 1)
    }
}
#endif
