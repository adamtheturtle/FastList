//
//  FastListSection.swift
//  FastList
//

import Foundation

/// A titled group of rows for sectioned ``FastList`` layouts.
public struct FastListSection<Item: Identifiable>: Identifiable where Item.ID: Hashable {
    public var id: AnyHashable
    public var title: String?
    public var items: [Item]

    public init(id: some Hashable, title: String? = nil, items: [Item]) {
        self.id = AnyHashable(id)
        self.title = title
        self.items = items
    }

    public init(_ title: String, items: [Item]) {
        self.init(id: title, title: title, items: items)
    }
}

/// Flattens sections into a single row array while recording which flat indexes are
/// section header rows (macOS group rows) versus item rows.
struct FastListSectionFlattening<Item: Identifiable> where Item.ID: Hashable {
    enum Row: Equatable {
        case header(sectionIndex: Int, title: String)
        case item(sectionIndex: Int, itemIndex: Int, id: Item.ID)
    }

    let rows: [Row]
    let itemsByFlatIndex: [Int: Item]

    init(sections: [FastListSection<Item>]) {
        var rows: [Row] = []
        var itemsByFlatIndex: [Int: Item] = [:]
        for (sectionIndex, section) in sections.enumerated() {
            if let title = section.title {
                rows.append(.header(sectionIndex: sectionIndex, title: title))
            }
            for (itemIndex, item) in section.items.enumerated() {
                let flat = rows.count
                rows.append(.item(sectionIndex: sectionIndex, itemIndex: itemIndex, id: item.id))
                itemsByFlatIndex[flat] = item
            }
        }
        self.rows = rows
        self.itemsByFlatIndex = itemsByFlatIndex
    }
}
