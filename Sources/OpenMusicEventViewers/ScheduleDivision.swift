import OpenMusicEventLexicon

public struct ScheduleDivision: Hashable, Identifiable, Sendable {
    public init(program: Program) {
        self.init(
            programID: program.id,
            title: program.title,
            icon: program.icon,
            eventPlaces: program.eventPlaces
        )
    }

    public init(
        programID: Program.ID?,
        title: String,
        icon: OME.SemanticIcon? = nil,
        eventPlaces: [EventPlace.ID] = []
    ) {
        self.programID = programID
        self.title = title
        self.icon = icon
        self.eventPlaces = eventPlaces
    }

    public let programID: Program.ID?
    public let title: String
    public let icon: OME.SemanticIcon?
    public let eventPlaces: [EventPlace.ID]

    public var id: String { programID?.description ?? "schedule" }
    public static let schedule = Self(programID: nil, title: "Schedule")

    public var systemImage: String {
        switch icon?.rawValue {
        case "heart": "heart"
        case "thumbsUp": "thumbs-up"
        case "personDoingYoga": "figure.mind.and.body"
        case "speechBubbles": "chatbubbles"
        case "gridOfSquares": "grid"
        default: "calendar"
        }
    }
}
