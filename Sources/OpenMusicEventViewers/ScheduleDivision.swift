public struct ScheduleDivision: Hashable, Identifiable, Sendable {
    public init(category: String?) {
        self.category = category
    }

    public var category: String?
    public var id: String { category ?? "schedule" }

    public static let schedule = Self(category: nil)

    public var systemImage: String {
        switch category {
        case nil:
            return "calendar"
        case "workshop":
            return "figure.mind.and.body"
        case "discussions":
            return "bubble.left.and.bubble.right"
        default:
            return "square.grid.2x2"
        }
    }

    public var title: String {
        switch category {
        case nil:
            return "Schedule"
        case "workshop":
            return "Workshops"
        default:
            return category?.scheduleDivisionTitle ?? "Schedule"
        }
    }
}

private extension String {
    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
