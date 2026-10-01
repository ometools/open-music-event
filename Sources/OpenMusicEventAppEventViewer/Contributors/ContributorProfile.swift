import ATProto
import ATProtoTypes
import Bluesky
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import SQLiteData

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

    var artworkAsset: OME.ImageAsset? { artworkDisplayImage?.asset }
    var artworkCacheContext: LocalImageCacheContext? { artworkDisplayImage?.cacheContext }
    var logoDisplayImage: DisplayImageAsset? { contributor.logoDisplayImage }
    var logoAsset: OME.ImageAsset? { logoDisplayImage?.asset }
    var logoCacheContext: LocalImageCacheContext? { logoDisplayImage?.cacheContext }
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
        return DisplayImageAsset(
            asset: OME.ImageAsset(
                source: .url(actorProfileAvatar),
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )
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
    let profile: ContributorProfile

    var id: Contributor.ID { profile.id }
    var contributorID: Contributor.ID { profile.contributorID }
    var contributor: Contributor { profile.contributor }

    func matchesSearch(_ query: String) -> Bool {
        profile.matchesSearch(query)
    }
}

extension ContributorListRow {
    static func all(
        eventID: Event.ID,
        hydration: ContributorProfile.Hydration
    ) -> some Statement<ContributorListRow> {
        Contributor
            .where { $0.event.eq(eventID) }
            .order { $0.name.collate(.nocase) }
            .select { contributor -> ContributorListRow.Columns in
                ContributorListRow.Columns(
                    profile: ContributorProfile.columns(
                        contributor: contributor,
                        hydration: hydration
                    )
                )
            }
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
