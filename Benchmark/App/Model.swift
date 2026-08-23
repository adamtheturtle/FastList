import SwiftUI

struct Item: Identifiable {
    let id: Int
    let name: String
    let subtitle: String
    let date: Date
    let badges: [String]

    var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}

func makeItems(_ count: Int) -> [Item] {
    let first = ["Ada", "Grace", "Alan", "Linus", "Margaret", "Dennis", "Barbara", "Ken"]
    let last = ["Lovelace", "Hopper", "Turing", "Torvalds", "Hamilton", "Ritchie", "Liskov", "Thompson"]
    let badgePool = ["Swift", "macOS", "UI", "Core", "Beta", "New", "Pro"]
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    return (0..<count).map { index in
        let name = "\(first[index % first.count]) \(last[(index / first.count) % last.count]) \(index)"
        let badgeCount = index % 3
        return Item(
            id: index,
            name: name,
            subtitle: "\(name.lowercased().replacingOccurrences(of: " ", with: "."))@example.com — record #\(index)",
            date: base.addingTimeInterval(Double(index) * 137),
            badges: Array(badgePool.prefix(badgeCount))
        )
    }
}

/// A deliberately non-trivial row: a gradient avatar, three text lines including a formatted
/// date, and a variable set of badges. This is the kind of content whose body is not free to
/// rebuild, which is where the difference between approaches shows up.
struct ComplexRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                .frame(width: 36, height: 36)
                .overlay(Text(item.initials).font(.caption.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(item.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            ForEach(item.badges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .padding(.vertical, 4)
    }
}
