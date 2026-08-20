import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

/// The complete server-facing projection produced by one validated source revision.
///
/// Every event is ready for catalog reads. The original source archive remains the authority for
/// installation-only data such as schedules, contributors, and file-backed images.
struct TangledSourceSnapshot: Equatable, Sendable {
    let revision: String
    let events: [OME.CalendarEvent]
    let posts: [OME.SourceDatabaseInsertion.CommunicationPost]

    init(
        revision: String,
        events: [OME.CalendarEvent],
        posts: [OME.SourceDatabaseInsertion.CommunicationPost]
    ) {
        self.revision = revision
        self.events = events
        self.posts = posts
    }

    init(
        validated insertion: OME.SourceDatabaseInsertion,
        revision: String
    ) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let posters = try insertion.posters.map {
            try decoder.decode(OME.Poster.self, from: encoder.encode($0))
        }
        let postersByEventID = Dictionary(grouping: posters) { poster in
            OME.Event.ID(
                organizerID: poster.id.organizerID,
                eventID: poster.id.eventID
            )
        }

        self.revision = revision
        self.events = try insertion.events.map { draft in
            guard let eventID = draft.id else {
                throw TangledSourceSnapshotError.missingValidatedEventID(draft.name)
            }
            guard let provenance = insertion.eventSourceProvenances.first(where: {
                $0.eventID == eventID
            }) else {
                throw TangledSourceSnapshotError.missingEventSourceProvenance(
                    OME.Event.reference(id: eventID).uri.description
                )
            }
            guard provenance.source.kind == .tangled else {
                throw TangledSourceSnapshotError.unsupportedEventSource(
                    provenance.source.reference
                )
            }
            guard provenance.source.ref == revision else {
                throw TangledSourceSnapshotError.eventSourceRevisionMismatch(
                    event: OME.Event.reference(id: eventID).uri.description,
                    expected: revision,
                    actual: provenance.source.ref
                )
            }

            let event = try decoder.decode(
                OME.Event.self,
                from: encoder.encode(draft)
            )
            return event.sourceCalendarEvent(
                posters: postersByEventID[eventID] ?? [],
                provenance: provenance.source
            )
        }
        self.posts = insertion.communicationPosts
    }

    static func empty(revision: String) -> Self {
        Self(revision: revision, events: [], posts: [])
    }
}

enum TangledSourceSnapshotError: Error, Equatable {
    case eventSourceRevisionMismatch(event: String, expected: String, actual: String?)
    case missingValidatedEventID(String)
    case missingEventSourceProvenance(String)
    case unsupportedEventSource(String)
}

private extension OME.Event {
    func sourceCalendarEvent(
        posters: [OME.Poster],
        provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) -> OME.CalendarEvent {
        var hydratedEvent = self
        hydratedEvent.images = hydratedEvent.images?.filter(\.isPubliclyReadable)

        return OME.CalendarEvent(
            uri: OME.Event.reference(id: id).uri,
            name: name,
            description: description,
            startsAt: startDate?.atStartOfDay(in: timeZone),
            endsAt: endDate?.at(hour: 23, minute: 59, second: 59, in: timeZone),
            status: sourceCalendarEventStatus,
            mode: sourceCalendarEventMode,
            locations: (locations ?? []).map(\.sourceCalendarEventLocation),
            links: sourceCalendarEventLinks,
            media: sourceCalendarEventMedia(posters: posters),
            organizer: OME.CalendarEvent.Organizer(id: id.organizerID),
            source: OME.CalendarEvent.Source(
                collection: OME.Event.nsid,
                sourceRecord: OME.SourceRecord(
                    kind: .tangled,
                    reference: provenance.reference,
                    ref: provenance.ref
                )
            ),
            timeZoneIdentifier: timeZone.identifier,
            event: hydratedEvent
        )
    }

    var sourceCalendarEventLinks: [OME.CalendarEvent.Link] {
        let eventLinks = (uris ?? []).map {
            OME.CalendarEvent.Link(name: $0.name, uri: $0.uri)
        }
        let mapLinks = (locations ?? []).flatMap { location in
            [
                location.appleMapsLink.map {
                    OME.CalendarEvent.Link(name: "Apple Maps", uri: $0, source: "location")
                },
                location.googleMapsLink.map {
                    OME.CalendarEvent.Link(name: "Google Maps", uri: $0, source: "location")
                },
            ]
            .compactMap { $0 }
        }
        return eventLinks + mapLinks
    }

    func sourceCalendarEventMedia(posters: [OME.Poster]) -> [OME.CalendarEvent.Media] {
        let posterMedia = posters
            .sorted {
                $0.id.posterID.rawValue.rawValue.localizedStandardCompare(
                    $1.id.posterID.rawValue.rawValue
                ) == .orderedAscending
            }
            .compactMap { poster -> OME.CalendarEvent.Media? in
                guard let url = poster.image.publicURL else { return nil }
                return OME.CalendarEvent.Media(
                    url: url,
                    alt: poster.title ?? name,
                    role: OME.ImageAsset.Role.poster.rawValue
                )
            }
        let eventMedia = (images ?? [])
            .enumerated()
            .filter { $0.element.role != .siteMap }
            .sorted {
                let lhsPriority = Self.sourceCalendarEventMediaPriority($0.element.role)
                let rhsPriority = Self.sourceCalendarEventMediaPriority($1.element.role)
                return lhsPriority == rhsPriority
                    ? $0.offset < $1.offset
                    : lhsPriority < rhsPriority
            }
            .compactMap { _, image -> OME.CalendarEvent.Media? in
                guard let url = image.publicURL else { return nil }
                return OME.CalendarEvent.Media(
                    url: url,
                    alt: name,
                    role: image.role.rawValue
                )
            }

        var seenURLs = Set<URL>()
        return (posterMedia + eventMedia).filter { seenURLs.insert($0.url).inserted }
    }

    static func sourceCalendarEventMediaPriority(_ role: OME.ImageAsset.Role) -> Int {
        switch role {
        case .poster: 0
        case .hero: 1
        case .photo: 2
        case .icon: 3
        case .logo: 4
        case .siteMap: 5
        }
    }

    var sourceCalendarEventStatus: OME.CalendarEvent.Status? {
        switch status {
        case .known(.cancelled): .cancelled
        case .known(.planned): .planned
        case .known(.postponed): .postponed
        case .known(.rescheduled): .rescheduled
        case .known(.scheduled): .scheduled
        case .unknown(let value): .unknown(String(describing: value))
        case nil: nil
        }
    }

    var sourceCalendarEventMode: OME.CalendarEvent.Mode? {
        switch mode {
        case .known(.hybrid): .hybrid
        case .known(.inPerson): .inPerson
        case .known(.virtual): .virtual
        case .unknown(let value): .unknown(String(describing: value))
        case nil: nil
        }
    }
}

private extension OME.Event.Location {
    var sourceCalendarEventLocation: OME.CalendarEvent.Location {
        OME.CalendarEvent.Location(
            name: address,
            latitude: coordinates.map { String($0.latitude) },
            longitude: coordinates.map { String($0.longitude) }
        )
    }
}

private extension OME.ImageAsset {
    var publicURL: URL? {
        guard case let .url(url) = source, !url.isFileURL else { return nil }
        return url
    }

    var isPubliclyReadable: Bool {
        publicURL != nil
    }
}
