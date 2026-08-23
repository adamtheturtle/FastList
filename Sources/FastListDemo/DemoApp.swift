//
//  DemoApp.swift
//  FastListDemo
//
//  A runnable showcase. `swift run FastListDemo` (or open Package.swift in Xcode and run
//  the FastListDemo scheme) launches a 50,000-row list that stays instant to scroll, filter,
//  and select - the whole point of the package.
//

import FastList
import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup("FastList Demo") {
            ContentView()
                .frame(minWidth: 520, minHeight: 600)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif
    }
}

private struct Contact: Identifiable {
    let id: Int
    let name: String
    let email: String
    var isFlagged: Bool
}

private struct ContentView: View {
    private static let pageSize = 500

    @State private var contacts: [Contact] = (1...Self.pageSize).map(Self.makeContact)
    @State private var nextID = Self.pageSize + 1
    @State private var selection: Set<Int> = []
    @State private var query = ""
    @State private var lastOpened = "-"
    @State private var scrollAnchor: Int?
    @State private var restoreAnchor: Int?
    /// `Contact.id` stays stable when its flag changes, so this token tells the recycled
    /// table cells that caller-owned row content changed.
    @State private var rowContentRevision = 0

    private var visible: [Contact] {
        guard !query.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FastList(visible, selection: $selection) { contact in
                row(contact)
                    .allowsHitTesting(false)
            }
            .onDoubleClick { open($0) }
            .onReturnKey { open($0) }
            .swipeActions(edge: .leading) { contact in
                [SwipeAction(title: "Flag", tint: .yellow, systemImage: "flag.fill") { toggleFlag(contact) }]
            }
            .swipeActions(edge: .trailing) { contact in
                [SwipeAction(title: "Delete", role: .destructive, systemImage: "trash") { delete(contact) }]
            }
            .rowContextMenu { contact, _ in
                [
                    .button(title: contact.isFlagged ? "Unflag" : "Flag") { toggleFlag(contact) },
                    .separator,
                    .button(title: "Delete") { delete(contact) }
                ]
            }
            .onTopRowChange { scrollAnchor = $0 }
            .scrollToRow(id: restoreAnchor) { restoreAnchor = nil }
            .onReachEnd(threshold: 20) { loadNextPage() }
            .rowContentID(rowContentRevision)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FastList - \(visible.count) rows")
                .font(.title2.bold())
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by name", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Selected: \(selection.count)  ·  Last opened: \(lastOpened)")
                Spacer()
                if let scrollAnchor {
                    Text("Top row: \(scrollAnchor)")
                }
                Button("Restore scroll") {
                    restoreAnchor = scrollAnchor
                }
                .disabled(scrollAnchor == nil)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func row(_ contact: Contact) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.headline)
                Text(contact.email).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if contact.isFlagged {
                Image(systemName: "flag.fill").foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func open(_ contact: Contact) {
        lastOpened = contact.name
    }

    private func toggleFlag(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].isFlagged.toggle()
        rowContentRevision += 1
    }

    private func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        selection.remove(contact.id)
    }

    private func loadNextPage() {
        // Skip paging while filtering: the visible slice is not the loaded corpus tail.
        guard query.isEmpty else { return }

        let page = (nextID ..< (nextID + Self.pageSize)).map(Self.makeContact)
        contacts.append(contentsOf: page)
        nextID += Self.pageSize
    }

    private static func makeContact(_ id: Int) -> Contact {
        Contact(id: id, name: "Contact \(id)", email: "contact\(id)@example.com", isFlagged: false)
    }
}
