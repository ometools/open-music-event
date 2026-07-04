import BlueskyActorCache
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData

@Selection
public struct ContributorProfile: Identifiable, Sendable {
    let contributor: OMERecord.Contributor
    let contributorActor: OMERecord.Contributor.Actor?
    let actorProfileHandle: String?
    let actorProfileDisplayName: String?
    let actorProfileDescription: String?
    let actorProfileAvatar: URL?

    init(
        contributor: OMERecord.Contributor,
        contributorActor: OMERecord.Contributor.Actor? = nil,
        actorProfileHandle: String? = nil,
        actorProfileDisplayName: String? = nil,
        actorProfileDescription: String? = nil,
        actorProfileAvatar: URL? = nil
    ) {
        self.contributor = contributor
        self.contributorActor = contributorActor
        self.actorProfileHandle = actorProfileHandle
        self.actorProfileDisplayName = actorProfileDisplayName
        self.actorProfileDescription = actorProfileDescription
        self.actorProfileAvatar = actorProfileAvatar
    }

    enum Hydration: Equatable, Sendable {
        case none
        case bskyActorProfile
    }

    public var id: OMERecord.Contributor.ID {
        contributor.id
    }

    var contributorID: OMERecord.ID<OMERecord.Contributor> {
        contributor.id.contributorID
    }

    var name: String {
        guard usesActorProfileAsPrimary else {
            return contributor.name
        }

        return actorProfileDisplayName?.nilIfEmpty
            ?? actorProfileHandle?.nilIfEmpty
            ?? contributor.name
    }

    var handle: String? {
        guard let handle = actorProfileHandle?.nilIfEmpty,
              handle != name
        else { return nil }

        return handle
    }

    var subtitle: String? {
        handle.map { "@\($0)" } ?? kindDisplayName
    }

    var bio: String? {
        guard usesActorProfileAsPrimary else {
            return contributor.displayBio
        }

        return actorProfileDescription?.nilIfEmpty ?? contributor.displayBio
    }

    var artworkAsset: OMERecord.ImageAsset? {
        actorAvatarAsset ?? contributor.preferredArtworkAsset
    }

    var artworkCacheContext: LocalImageCacheContext? {
        actorAvatarAsset == nil ? .init(contributorID: contributor.id) : nil
    }

    var kindDisplayName: String? {
        contributor.kind?.displayName
    }

    var links: [ExternalPlatform.Link]? {
        contributor.links
    }

    var logoAsset: OMERecord.ImageAsset? {
        contributor.images?.imageAsset(role: .logo)
    }

    var logoCacheContext: LocalImageCacheContext? {
        logoAsset == nil ? nil : .init(contributorID: contributor.id)
    }

    var usesActorProfileAsPrimary: Bool {
        guard let contributorActor else {
            return false
        }

        return contributor.isGeneratedScheduleActorContributor(
            actor: contributorActor,
            actorProfileHandle: actorProfileHandle
        )
    }

    var actorProfileLoadRequest: ActorProfileLoadRequest? {
        contributorActor.map(ActorProfileLoadRequest.init)
    }

    func matchesSearch(_ query: String) -> Bool {
        name.localizedStandardContains(query)
            || kindDisplayName?.localizedStandardContains(query) == true
            || handle?.localizedStandardContains(query) == true
            || bio?.localizedStandardContains(query) == true
    }

    private var actorAvatarAsset: OMERecord.ImageAsset? {
        guard usesActorProfileAsPrimary, let actorProfileAvatar else {
            return nil
        }

        return OMERecord.ImageAsset(
            source: .url(actorProfileAvatar),
            role: .photo,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
    }

    struct ActorProfileLoadRequest: Equatable, Sendable {
        var actor: OMERecord.Contributor.Actor
    }
}

extension ContributorProfile {
    static func all(
        eventID: OMERecord.Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { $0.name.collate(.nocase) }
            .select { contributor -> ContributorProfile.Columns in
                Self.eventColumns(
                    contributor: contributor,
                    eventID: eventID,
                    hydration: hydration
                )
            }
    }

    static func one(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        eventID: OMERecord.Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.contributorID.eq(contributorID) }
            .select { contributor -> ContributorProfile.Columns in
                Self.eventColumns(
                    contributor: contributor,
                    eventID: eventID,
                    hydration: hydration
                )
            }
    }

    static func forPerformance(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        hydration: Hydration
    ) -> some Statement<ContributorProfile> {
        OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { contributor in
                OMERecord.Performance.Contributors
                    .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
                    .where { $0.performanceID.eventID.eq(eventID.eventID) }
                    .where { $0.performanceID.performanceID.eq(performanceID) }
                    .where { $0.contributorID.eq(contributor.id.contributorID) }
                    .exists()
            }
            .order { $0.name.collate(.nocase) }
            .select { contributor -> ContributorProfile.Columns in
                Self.performanceColumns(
                    contributor: contributor,
                    performanceID: performanceID,
                    eventID: eventID,
                    hydration: hydration
                )
            }
    }

    fileprivate static func eventColumns(
        contributor: OMERecord.Contributor.TableColumns,
        eventID: OMERecord.Event.ID,
        hydration: Hydration
    ) -> ContributorProfile.Columns {
        switch hydration {
        case .none:
            ContributorProfile.Columns(
                contributor: contributor,
                contributorActor: eventContributorActorExpression(eventID: eventID),
                actorProfileHandle: nullStringExpression(),
                actorProfileDisplayName: nullStringExpression(),
                actorProfileDescription: nullStringExpression(),
                actorProfileAvatar: nullURLExpression()
            )

        case .bskyActorProfile:
            ContributorProfile.Columns(
                contributor: contributor,
                contributorActor: eventContributorActorExpression(eventID: eventID),
                actorProfileHandle: eventActorProfileHandleExpression(eventID: eventID),
                actorProfileDisplayName: eventActorProfileDisplayNameExpression(eventID: eventID),
                actorProfileDescription: eventActorProfileDescriptionExpression(eventID: eventID),
                actorProfileAvatar: eventActorProfileAvatarExpression(eventID: eventID)
            )
        }
    }

    private static func performanceColumns(
        contributor: OMERecord.Contributor.TableColumns,
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        hydration: Hydration
    ) -> ContributorProfile.Columns {
        switch hydration {
        case .none:
            ContributorProfile.Columns(
                contributor: contributor,
                contributorActor: performanceContributorActorExpression(
                    performanceID: performanceID,
                    eventID: eventID
                ),
                actorProfileHandle: nullStringExpression(),
                actorProfileDisplayName: nullStringExpression(),
                actorProfileDescription: nullStringExpression(),
                actorProfileAvatar: nullURLExpression()
            )

        case .bskyActorProfile:
            ContributorProfile.Columns(
                contributor: contributor,
                contributorActor: performanceContributorActorExpression(
                    performanceID: performanceID,
                    eventID: eventID
                ),
                actorProfileHandle: performanceActorProfileHandleExpression(
                    performanceID: performanceID,
                    eventID: eventID
                ),
                actorProfileDisplayName: performanceActorProfileDisplayNameExpression(
                    performanceID: performanceID,
                    eventID: eventID
                ),
                actorProfileDescription: performanceActorProfileDescriptionExpression(
                    performanceID: performanceID,
                    eventID: eventID
                ),
                actorProfileAvatar: performanceActorProfileAvatarExpression(
                    performanceID: performanceID,
                    eventID: eventID
                )
            )
        }
    }

    private static func nullStringExpression() -> some QueryExpression<String?> {
        #sql("NULL", as: String?.self)
    }

    private static func nullURLExpression() -> some QueryExpression<URL?> {
        #sql("NULL", as: URL?.self)
    }

    private static func eventContributorActorExpression(
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<OMERecord.Contributor.Actor?> {
        #sql(
            """
            COALESCE(
              "contributors"."did",
              (
              SELECT "performanceContributors"."contributorActor"
              FROM "performanceContributors"
              WHERE "performanceContributors"."organizerID" = \(eventID.organizerID)
                AND "performanceContributors"."eventID" = \(eventID.eventID)
                AND "performanceContributors"."contributorID" = "contributors"."contributorID"
                AND "performanceContributors"."contributorActor" IS NOT NULL
              ORDER BY "performanceContributors"."performanceID"
              LIMIT 1
              )
            )
            """,
            as: OMERecord.Contributor.Actor?.self
        )
    }

    private static func performanceContributorActorExpression(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<OMERecord.Contributor.Actor?> {
        #sql(
            """
            COALESCE(
              "contributors"."did",
              (
              SELECT "performanceContributors"."contributorActor"
              FROM "performanceContributors"
              WHERE "performanceContributors"."organizerID" = \(eventID.organizerID)
                AND "performanceContributors"."eventID" = \(eventID.eventID)
                AND "performanceContributors"."performanceID" = \(performanceID)
                AND "performanceContributors"."contributorID" = "contributors"."contributorID"
                AND "performanceContributors"."contributorActor" IS NOT NULL
              LIMIT 1
              )
            )
            """,
            as: OMERecord.Contributor.Actor?.self
        )
    }

    private static func eventActorProfileHandleExpression(
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        eventActorProfileExpression("handle", eventID: eventID, as: String?.self)
    }

    private static func eventActorProfileDisplayNameExpression(
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        eventActorProfileExpression("displayName", eventID: eventID, as: String?.self)
    }

    private static func eventActorProfileDescriptionExpression(
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        eventActorProfileExpression("description", eventID: eventID, as: String?.self)
    }

    private static func eventActorProfileAvatarExpression(
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<URL?> {
        eventActorProfileExpression("avatar", eventID: eventID, as: URL?.self)
    }

    private static func performanceActorProfileHandleExpression(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        performanceActorProfileExpression(
            "handle",
            performanceID: performanceID,
            eventID: eventID,
            as: String?.self
        )
    }

    private static func performanceActorProfileDisplayNameExpression(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        performanceActorProfileExpression(
            "displayName",
            performanceID: performanceID,
            eventID: eventID,
            as: String?.self
        )
    }

    private static func performanceActorProfileDescriptionExpression(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<String?> {
        performanceActorProfileExpression(
            "description",
            performanceID: performanceID,
            eventID: eventID,
            as: String?.self
        )
    }

    private static func performanceActorProfileAvatarExpression(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some QueryExpression<URL?> {
        performanceActorProfileExpression(
            "avatar",
            performanceID: performanceID,
            eventID: eventID,
            as: URL?.self
        )
    }

    private static func eventActorProfileExpression<Value>(
        _ columnName: String,
        eventID: OMERecord.Event.ID,
        as type: Value.Type
    ) -> some QueryExpression<Value> {
        #sql(
            """
            (
              SELECT "blueskyActorProfiles".\(raw: columnName)
              FROM "blueskyActorProfileCacheEntries"
              JOIN "blueskyActorProfiles"
                ON "blueskyActorProfiles"."did" = "blueskyActorProfileCacheEntries"."did"
              WHERE "blueskyActorProfileCacheEntries"."actor" = COALESCE(
                "contributors"."did",
                (
                SELECT "performanceContributors"."contributorActor"
                FROM "performanceContributors"
                WHERE "performanceContributors"."organizerID" = \(eventID.organizerID)
                  AND "performanceContributors"."eventID" = \(eventID.eventID)
                  AND "performanceContributors"."contributorID" = "contributors"."contributorID"
                  AND "performanceContributors"."contributorActor" IS NOT NULL
                ORDER BY "performanceContributors"."performanceID"
                LIMIT 1
                )
              )
              LIMIT 1
            )
            """,
            as: type
        )
    }

    private static func performanceActorProfileExpression<Value>(
        _ columnName: String,
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        as type: Value.Type
    ) -> some QueryExpression<Value> {
        #sql(
            """
            (
              SELECT "blueskyActorProfiles".\(raw: columnName)
              FROM "blueskyActorProfileCacheEntries"
              JOIN "blueskyActorProfiles"
                ON "blueskyActorProfiles"."did" = "blueskyActorProfileCacheEntries"."did"
              WHERE "blueskyActorProfileCacheEntries"."actor" = COALESCE(
                "contributors"."did",
                (
                SELECT "performanceContributors"."contributorActor"
                FROM "performanceContributors"
                WHERE "performanceContributors"."organizerID" = \(eventID.organizerID)
                  AND "performanceContributors"."eventID" = \(eventID.eventID)
                  AND "performanceContributors"."performanceID" = \(performanceID)
                  AND "performanceContributors"."contributorID" = "contributors"."contributorID"
                  AND "performanceContributors"."contributorActor" IS NOT NULL
                LIMIT 1
                )
              )
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
    @Column(as: [OMERecord.Stage].JSONRepresentation.self)
    let scheduledStages: [OMERecord.Stage]
    @Column(as: [OMERecord.Stage].JSONRepresentation.self)
    let eventStages: [OMERecord.Stage]

    var id: OMERecord.Contributor.ID {
        profile.id
    }

    var contributorID: OMERecord.ID<OMERecord.Contributor> {
        profile.contributorID
    }

    var contributor: OMERecord.Contributor {
        profile.contributor
    }

    var stageContext: ContributorStageContext {
        ContributorStageContext(
            contributorID: contributorID,
            scheduledStages: scheduledStages,
            stages: eventStages
        )
    }

    func matchesSearch(_ query: String) -> Bool {
        profile.matchesSearch(query)
    }
}

extension ContributorListRow {
    static func all(
        eventID: OMERecord.Event.ID,
        hydration: ContributorProfile.Hydration
    ) -> some Statement<ContributorListRow> {
        OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { $0.name.collate(.nocase) }
            .leftJoin(OMERecord.Stage.all) { contributor, stage in
                stage.id.organizerID.eq(eventID.organizerID)
                    .and(stage.id.eventID.eq(eventID.eventID))
            }
            .group(by: { contributor, _ in
                contributor.id
            })
            .select { contributor, stage -> ContributorListRow.Columns in
                let isScheduledStage = #sql(
                    """
                    EXISTS (
                      SELECT 1
                      FROM "performances"
                      JOIN "performanceContributors"
                        ON "performanceContributors"."organizerID" = "performances"."organizerID"
                        AND "performanceContributors"."eventID" = "performances"."eventID"
                        AND "performanceContributors"."performanceID" = "performances"."performanceID"
                      WHERE "performances"."organizerID" = \(eventID.organizerID)
                        AND "performances"."eventID" = \(eventID.eventID)
                        AND "performances"."stageID" = "stages"."stageID"
                        AND "performanceContributors"."contributorID" = "contributors"."contributorID"
                    )
                    """,
                    as: Bool.self
                )

                return ContributorListRow.Columns(
                    profile: ContributorProfile.eventColumns(
                        contributor: contributor,
                        eventID: eventID,
                        hydration: hydration
                    ),
                    scheduledStages: stage.jsonGroupArray(
                        distinct: true,
                        filter: isScheduledStage
                    ),
                    eventStages: stage.jsonGroupArray(distinct: true)
                )
            }
    }
}

extension Collection where Element == ContributorProfile {
    var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
        var actors: Set<OMERecord.Contributor.Actor> = []
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
