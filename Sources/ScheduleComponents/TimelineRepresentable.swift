import Foundation

public protocol DateIntervalRepresentable {
    var dateInterval: DateInterval { get }
}

public protocol TimelineCard: DateIntervalRepresentable, Equatable, Identifiable {
    var groupWidth: Range<Int> { get }
}

public extension TimelineCard {
    var groupWidth: Range<Int> { 0..<0 }
}

public struct TimelineWrapper<Value: DateIntervalRepresentable & Equatable & Identifiable>: TimelineCard {
    public var groupWidth: Range<Int>
    public var item: Value

    public init(groupWidth: Range<Int>, item: Value) {
        self.groupWidth = groupWidth
        self.item = item
    }

    public var id: Value.ID { item.id }
    public var dateInterval: DateInterval { item.dateInterval }
}

public extension Collection where Element: DateIntervalRepresentable & Equatable & Identifiable {
    var groupedToPreventOverlaps: [TimelineWrapper<Element>] {
        var columns: [[Element]] = [[]]

        for item in sorted(by: \.dateInterval.start, and: \.dateInterval.end) {
            for (index, column) in columns.enumerated() {
                if let lastItem = column.last,
                   item.dateInterval.intersects(lastItem.dateInterval, adjacentIntersects: false) {
                    if !columns.indices.contains(index + 1) {
                        columns.append([item])
                    }
                    continue
                } else {
                    columns[index].append(item)
                    break
                }
            }
        }

        var output: [TimelineWrapper<Element>] = []
        for (columnIndex, column) in columns.enumerated() {
            for item in column {
                var endColumn = columnIndex
                for candidateColumnIndex in columnIndex..<columns.count {
                    if !columns[candidateColumnIndex].contains(where: {
                        item.dateInterval.intersects($0.dateInterval, adjacentIntersects: false)
                    }) {
                        endColumn = candidateColumnIndex
                    }
                }
                output.append(TimelineWrapper(groupWidth: columnIndex..<endColumn, item: item))
            }
        }

        return output
    }
}

public extension Collection {
    func sorted<T: Comparable, U: Comparable>(
        by keyPath: KeyPath<Element, T>,
        and secondaryKeyPath: KeyPath<Element, U>
    ) -> [Element] {
        sorted {
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
            return intersects(other)
        }
        if start == other.end || end == other.start {
            return false
        }
        return intersects(other)
    }
}
