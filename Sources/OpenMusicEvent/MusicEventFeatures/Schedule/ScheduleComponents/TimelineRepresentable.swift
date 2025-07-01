//
//  File.swift
//  
//
//  Created by Woodrow Melling on 5/28/23.
//

import Foundation

public protocol DateIntervalRepresentable { // TODO: Replace All Range<Date> with DateInterval
    var dateInterval: DateInterval { get }
}


public protocol TimelineCard: Equatable, Identifiable, DateIntervalRepresentable {
    var groupWidth: Range<Int> { get }
}

public extension TimelineCard {
    var groupWidth: Range<Int> { 1..<1 }
}

public struct TimelineWrapper<Value: Identifiable & Equatable & DateIntervalRepresentable>: TimelineCard, Equatable, Identifiable {
    public var groupWidth: Range<Int>
    public var item: Value
    
    public init(groupWidth: Range<Int>, item: Value) {
        self.groupWidth = groupWidth
        self.item = item
    }
    
    public var id: Value.ID { item.id }
    public var dateInterval: DateInterval { item.dateInterval }
}

extension Collection where Element: DateIntervalRepresentable & Equatable & Identifiable {
    public var groupedToPreventOverlaps: [TimelineWrapper<Element>] {
        var columns: [[Element]] = [[]]
        
        let sortedItems = self.sorted(
            by: \.dateInterval.start,
            and: \.dateInterval.end
        )
        
        for item in sortedItems {
            for (idx, column) in columns.enumerated() {
                // Has overlap
                if let lastItem = column.last, item.dateInterval.intersects(lastItem.dateInterval, adjacentIntersects: false) {
                    if !columns.indices.contains(idx + 1) {
                        columns.append([item])
                    }
                    
                    continue
                } else {
                    columns[idx].append(item)
                    break
                }
            }
        }
        
        var output: [TimelineWrapper<Element>] = []
        
        for (columnIdx, column) in columns.enumerated() {
            for item in column {
                var endColumn = columnIdx
                for columnIdx in (columnIdx)..<columns.count {
                    if !columns[columnIdx].contains(where: {
                        item.dateInterval.intersects($0.dateInterval, adjacentIntersects: false)
                    }) {
                        endColumn = columnIdx
                    }
                }
                
                
                output.append(TimelineWrapper(groupWidth: columnIdx..<endColumn, item: item))
            }
        }

        return output
    }
}


extension Collection {
    public func sorted<T, U>(by keyPath: KeyPath<Element, T>, and secondaryKeyPath: KeyPath<Element, U>) -> [Element] where T : Comparable, U: Comparable {
        self.sorted {
            if $0[keyPath: keyPath] == $1[keyPath: keyPath] {
                return $0[keyPath: secondaryKeyPath] < $1[keyPath: secondaryKeyPath]
            } else {
                return $0[keyPath: keyPath] < $1[keyPath: keyPath]
            }
        }
    }
}

public extension DateInterval {
    func intersects(_ other: DateInterval, adjacentIntersects: Bool) -> Bool {
        if adjacentIntersects {
            self.intersects(other)
        } else {
            if self.intersects(other) && start == other.end || end == other.start {
                false
            } else {
                self.intersects(other)
            }
        }

    }
}
