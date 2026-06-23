//
//  Example.swift
//  FastList
//
//  A compile-checked usage example. Drop a `#Preview { ExampleList() }` here in Xcode to
//  see it live; the macro is omitted so the package also builds from the command line.
//

import SwiftUI

#if DEBUG
private struct Person: Identifiable {
    let id: Int
    let name: String
    let email: String
}

private struct ExampleList: View {
    @State private var people: [Person] = (1...10_000).map {
        Person(id: $0, name: "Person \($0)", email: "person\($0)@example.com")
    }
    @State private var selection: Set<Int> = []

    var body: some View {
        FastList(people, selection: $selection) { person in
            HStack {
                VStack(alignment: .leading) {
                    Text(person.name).font(.headline)
                    Text(person.email).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            // The whole row is decorative — let clicks fall through to the table.
            .allowsHitTesting(false)
        }
        .onDoubleClick { person in print("open \(person.name)") }
        .onReturnKey { person in print("open \(person.name)") }
        .swipeActions(edge: .trailing) { person in
            [SwipeAction(title: "Delete", role: .destructive, systemImage: "trash") {
                people.removeAll { $0.id == person.id }
            }]
        }
        .swipeActions(edge: .leading) { _ in
            [SwipeAction(title: "Flag", tint: .yellow, systemImage: "flag.fill") {}]
        }
        .rowContextMenu { person in
            [
                .button(title: "Copy Email") {},
                .separator,
                .button(title: "Delete") { people.removeAll { $0.id == person.id } }
            ]
        }
        .frame(width: 360, height: 480)
    }
}
#endif
