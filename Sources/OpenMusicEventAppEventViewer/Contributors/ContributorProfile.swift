import ATProto
import ATProtoTypes
import Bluesky
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import SQLiteData
import class GRDB.DatabaseFunction

@Selection
public struct ContributorProfile: Identifiable, Sendable {
    let contributor: Contributor
    let actorProfileHandle: String?
    let actorProfileDisplayName: String?
    let actorProfileDescription: String?
    let actorProfileAvatar: URL?

    init(
        contributor: Contributor,
        actorProfileHandle: String? = nil,
        actorProfileDisplayName: String? = nil,
        actorProfileDescription: String? = nil,
        actorProfileAvatar: URL? = nil
    ) {
        self.contributor = contributor
        self.actorProfileHandle = actorProfileHandle
        self.actorProfileDisplayName = actorProfileDisplayName
        self.actorProfileDescription = actorProfileDescription
        self.actorProfileAvatar = actorProfileAvatar
    }

    enum Hydration: Equatable, Sendable {
        case none
        case bskyActorProfile
    }

    public var id: Contributor.ID { contributor.id }
    var contributorID: Contributor.ID { contributor.id }
    var contributorActor: DID? { contributor.subject }

    // The organizer-authored snapshot is primary. A subject DID is an assertion,
    // not permission for the subject's current profile to overwrite this record.
    var name: String { contributor.name }
    var bio: String? { contributor.description?.nilIfEmpty }

    var handle: String? {
        guard let handle = actorProfileHandle?.nilIfEmpty,
              handle != name
        else { return nil }
        return handle
    }

    var subtitle: String? { handle.map { "@\($0)" } }

    var artworkDisplayImage: DisplayImageAsset? {
        contributor.artworkDisplayImage ?? actorAvatarDisplayImage
    }

    var logoDisplayImage: DisplayImageAsset? { contributor.logoDisplayImage }
    var links: [OME.Link]? { contributor.links }

    var heroImageSources: [HeroImageSource] {
        [
            artworkDisplayImage.map(HeroImageSource.primaryImage),
            logoDisplayImage.map(HeroImageSource.logo),
        ].compactMap { $0 }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        [
            logoDisplayImage.map(HeroImageTitleSource.logo),
            .title,
        ].compactMap { $0 }
    }

    var usesActorProfileAsPrimary: Bool { false }

    var actorProfileLoadRequest: ActorProfileLoadRequest? {
        contributor.subject.map { ActorProfileLoadRequest(actor: $0) }
    }

    func matchesSearch(_ query: String) -> Bool {
        name.localizedStandardContains(query)
            || handle?.localizedStandardContains(query) == true
            || bio?.localizedStandardContains(query) == true
    }

    private var actorAvatarDisplayImage: DisplayImageAsset? {
        guard let actorProfileAvatar else { return nil }
        return OME.Image(
            source: .known(.url(actorProfileAvatar)),
            role: .known(.photo)
        ).displayImageAsset()
    }

    struct ActorProfileLoadRequest: Equatable, Sendable {
        var actor: DID
    }
}

extension ContributorProfile {
    static func all(
        eventID: Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        Contributor
            .where { $0.event.eq(eventID) }
            .order { $0.name.collate(.nocase) }
            .select { contributor -> ContributorProfile.Columns in
                columns(contributor: contributor, hydration: hydration)
            }
    }

    static func one(
        contributorID: Contributor.ID,
        eventID: Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        Contributor
            .where { $0.id.eq(contributorID) }
            .where { $0.event.eq(eventID) }
            .select { contributor -> ContributorProfile.Columns in
                columns(contributor: contributor, hydration: hydration)
            }
    }

    static func forProgramItem(
        programItemID: ProgramItem.ID,
        eventID: Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        let contributorTable = Contributor.tableName
        let itemTable = ProgramItem.tableName
        return Contributor
            .where { $0.event.eq(eventID) }
            .where { _ in
                #sql(
                    """
                    EXISTS (
                      SELECT 1
                      FROM \(quote: itemTable) AS "item"
                      JOIN json_each("item"."credits") AS "credit"
                      WHERE "item"."id" = \(programItemID)
                        AND "item"."event" = \(eventID)
                        AND json_extract("credit"."value", '$.contributor') = \(quote: contributorTable)."id"
                    )
                    """,
                    as: Bool.self
                )
            }
            .order { $0.name.collate(.nocase) }
            .select { contributor -> ContributorProfile.Columns in
                columns(contributor: contributor, hydration: hydration)
            }
    }

    fileprivate static func columns(
        contributor: Contributor.TableColumns,
        hydration: Hydration
    ) -> ContributorProfile.Columns {
        switch hydration {
        case .none:
            ContributorProfile.Columns(
                contributor: contributor,
                actorProfileHandle: #sql("NULL", as: String?.self),
                actorProfileDisplayName: #sql("NULL", as: String?.self),
                actorProfileDescription: #sql("NULL", as: String?.self),
                actorProfileAvatar: #sql("NULL", as: URL?.self)
            )
        case .bskyActorProfile:
            ContributorProfile.Columns(
                contributor: contributor,
                actorProfileHandle: actorProfileExpression("handle", as: String?.self),
                actorProfileDisplayName: actorProfileExpression("displayName", as: String?.self),
                actorProfileDescription: actorProfileExpression("description", as: String?.self),
                actorProfileAvatar: actorProfileExpression("avatar", as: URL?.self)
            )
        }
    }

    private static func actorProfileExpression<Value>(
        _ column: String,
        as type: Value.Type
    ) -> some QueryExpression<Value> {
        let profileTable = BlueskyActorProfile.tableName
        let contributorTable = Contributor.tableName
        return #sql(
            """
            (
              SELECT \(quote: profileTable).\(raw: column)
              FROM \(quote: profileTable)
              WHERE \(quote: profileTable)."did" = \(quote: contributorTable)."subject"
              LIMIT 1
            )
            """,
            as: type
        )
    }
}

@Selection
struct ContributorListRow: Identifiable, Sendable {
    let id: Contributor.ID
    let eventID: Event.ID
    let name: String
    let subject: DID?
    let actorProfileHandle: String?
    let actorProfileAvatar: URL?
    @Column(as: OME.Image.JSONRepresentation?.self)
    let artwork: OME.Image?
    @Column(as: [ContributorListStage].JSONRepresentation.self)
    let stages: [ContributorListStage]

    var contributorID: Contributor.ID { id }
    var handle: String? {
        guard let value = actorProfileHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value != name else { return nil }
        return value
    }
    var subtitle: String? { handle.map { "@\($0)" } }
    var artworkDisplayImage: DisplayImageAsset? {
        artwork?.displayImageAsset(recordID: eventID)
            ?? actorProfileAvatar.flatMap {
                OME.Image(source: .known(.url($0)), role: .known(.photo)).displayImageAsset()
            }
    }
}

extension ContributorListRow {
    static func all(
        eventID: Event.ID,
        hydration: ContributorProfile.Hydration,
        search: String = ""
    ) -> some Statement<ContributorListRow> {
        let profiles: QueryFragment = hydration == .bskyActorProfile
            ? "\(BlueskyActorProfile.self)"
            : "(SELECT NULL AS did, NULL AS handle, NULL AS avatar) AS \(quote: BlueskyActorProfile.tableName)"
        let filter: SQLQueryExpression<Bool> = search.isEmpty ? #sql("1") : #sql(
            """
            (ome_contributor_contains(\(Contributor.name), \(search))
             OR ome_contributor_contains(\(Contributor.description), \(search))
             OR ome_contributor_contains(\(BlueskyActorProfile.handle), \(search)))
            """, as: Bool.self
        )
        let artwork = ContributorArtworkQuery.image(media: Contributor.media.queryFragment)
        return #sql(
            """
            WITH associations(contributorID, placeID) AS MATERIALIZED (
                SELECT json_extract(credit.value, '$.contributor'), item.eventPlace
                FROM \(ProgramItem.self) AS item, json_each(item.credits) AS credit
                WHERE item.event = \(eventID) AND item.eventPlace IS NOT NULL
                  AND json_extract(credit.value, '$.contributor') IS NOT NULL
                UNION
                SELECT lineup.value, place.id
                FROM \(EventPlace.self) AS place, json_each(place.kind, '$.lineup') AS lineup
                WHERE place.event = \(eventID)
                  AND json_extract(place.kind, '$.$type') = 'events.openmusic.defs#eventPlaceStage'
            ), orderedStages AS MATERIALIZED (
                SELECT associations.contributorID, place.id, place.name,
                       CASE WHEN json_extract(place.kind, '$.$type') = 'events.openmusic.defs#eventPlaceStage'
                            THEN json_extract(place.kind, '$.color') END AS color
                FROM associations JOIN \(EventPlace.self) AS place ON place.id = associations.placeID
                WHERE place.event = \(eventID)
                ORDER BY json_extract(place.kind, '$.sortIndex') IS NULL,
                         json_extract(place.kind, '$.sortIndex'),
                         place.name COLLATE swiftLocalizedStandardCompare, place.id
            ), contexts AS (
                SELECT contributorID, json_group_array(json_object('id', id, 'name', name, 'color', color)) AS stages
                FROM orderedStages GROUP BY contributorID
            )
            SELECT \(Contributor.id), \(Contributor.event), \(Contributor.name), \(Contributor.subject),
                   \(BlueskyActorProfile.handle), \(BlueskyActorProfile.avatar), \(artwork),
                   COALESCE(contexts.stages, '[]')
            FROM \(Contributor.self)
            LEFT JOIN \(profiles) ON \(BlueskyActorProfile.did) = \(Contributor.subject)
            LEFT JOIN contexts ON contexts.contributorID = \(Contributor.id)
            WHERE \(Contributor.event) = \(eventID) AND \(filter)
            ORDER BY \(Contributor.name) COLLATE NOCASE
            """, as: ContributorListRow.self
        )
    }
}

struct ContributorListStage: Codable, Sendable, Equatable {
    let id: EventPlace.ID
    let name: String
    let color: Int?
}

struct ContributorListRequest: FetchKeyRequest {
    let eventID: Event.ID
    var search = ""

    func fetch(_ db: Database) throws -> [ContributorListRow] {
        db.add(function: GRDB.DatabaseFunction("ome_contributor_contains", argumentCount: 2, pure: true) { values in
            guard let text = String.fromDatabaseValue(values[0]),
                  let term = String.fromDatabaseValue(values[1]) else { return false }
            return text.localizedStandardContains(term)
        })
        return try ContributorListRow.all(
            eventID: eventID, hydration: .bskyActorProfile,
            search: search.trimmingCharacters(in: .whitespacesAndNewlines)
        ).fetchAll(db)
    }
}

extension Collection where Element == ContributorProfile {
    var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
        var actors: Set<DID> = []
        var requests: [ContributorProfile.ActorProfileLoadRequest] = []
        for profile in self {
            guard let request = profile.actorProfileLoadRequest,
                  actors.insert(request.actor).inserted
            else { continue }
            requests.append(request)
        }
        return requests
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
