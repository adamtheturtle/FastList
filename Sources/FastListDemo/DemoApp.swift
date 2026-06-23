//
//  DemoApp.swift
//  FastListDemo
//
//  A runnable showcase. `swift run FastListDemo` (or open Package.swift in Xcode and run
//  the FastListDemo scheme) launches a 50,000-row list that stays instant to scroll, filter,
//  and select — the whole point of the package.
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
        .windowStyle(.titleBar)
    }
}

private struct Contact: Identifiable {
    let id: Int
    let name: String
    let email: String
    var isFlagged: Bool
}

private struct ContentView: View {
    @State private var contacts: [Contact] = (1...50_000).map {
        Contact(id: $0, name: "Contact \($0)", email: "contact\($0)@example.com", isFlagged: false)
    }
    @State private var selection: Set<Int> = []
    @State private var query = ""
    @State private var lastOpened = "—"

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
            .rowContextMenu { contact in
                [
                    .button(title: contact.isFlagged ? "Unflag" : "Flag") { toggleFlag(contact) },
                    .separator,
                    .button(title: "Delete") { delete(contact) }
                ]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FastList — \(visible.count) rows")
                .font(.title2.bold())
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by name", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("Selected: \(selection.count)  ·  Last opened: \(lastOpened)")
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
    }

    private func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        selection.remove(contact.id)
    }
}
