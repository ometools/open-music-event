//
//  File.swift
//  
//
//  Created by Woodrow Melling on 6/3/24.
//

import Foundation
import Collections

extension Collection {
    var hasElements: Bool {
        !self.isEmpty
    }

    var nilIfEmpty: Self? {
        self.isEmpty ? nil : self
    }

    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Set {
    func sorted(by key: (Element) -> some Comparable) -> OrderedSet<Element> {
        OrderedSet(self.sorted(by: { key($0) < key($1) }))
    }
}

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: true
        case .some(let wrapped): wrapped.isEmpty
        }
    }

    var hasElements: Bool {
        !isNilOrEmpty
    }
}
