public struct AppViewIngestionConfiguration: Equatable, Sendable {
    public init(
        endpoint: String,
        subscriptionID: String = "hydrant|community.lexicon.calendar.event"
    ) {
        self.endpoint = endpoint
        self.subscriptionID = subscriptionID
    }

    public var endpoint: String
    public var subscriptionID: String
}
