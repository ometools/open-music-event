//
//  ContributorDetail.swift
//  open-music-event
//
//  Created by Woodrow Melling on 7/1/26.
//

import OpenMusicEventLexicon
import ATProto
import ATProtoTypes
import Bluesky
import ComposableForms
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import Sharing
import SQLiteData
import Tagged
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import ATProto


@Feature
public struct ContributorDetail {
    public init() {}

    public struct State: Identifiable {
        public let contributorID: Contributor.ID
        public let eventID: Event.ID

        @FetchOne var event: Event?
        @FetchOne var profile: ContributorProfile?

        public init(
            contributorID: Contributor.ID,
            eventID: Event.ID? = nil
        ) {
            @Dependency(EventViewerContext.self) var eventViewer

            self.contributorID = contributorID
            self.eventID = eventID ?? eventViewer.eventID
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: self.eventID)
            )
            _event = FetchOne(Event.where { $0.id.eq(self.eventID) })
            _profile = FetchOne(
                ContributorProfile.one(
                    contributorID: contributorID,
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _lineupStages = FetchAll(
                ContributorDetail.lineupStagesQuery(
                    contributorID: contributorID,
                    eventID: self.eventID
                )
            )
            _performanceRows = FetchAll(
                PerformanceRow.forContributor(
                    contributorID: contributorID,
                    eventID: self.eventID
                )
            )
        }

        public var id: Contributor.ID { contributorID }

        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public var destination: Destination.State?
        @FetchAll public var lineupStages: [EventPlace]
        @FetchAll var performanceRows: [PerformanceRow]

        var contributor: Contributor? {
            profile?.contributor
        }

        var stageContext: ContributorStageContext {
            ContributorStageContext(
                contributorID: contributorID,
                performanceRows: performanceRows,
                lineupStages: lineupStages
            )
        }

        var heroImageSources: [HeroImageSource] {
            (profile?.heroImageSources ?? []) + (event?.heroImageSources ?? [])
        }

        var actorProfileLoadRequest: ContributorProfile.ActorProfileLoadRequest? {
            profile?.actorProfileLoadRequest
        }

        var contributorActor: DID? {
            profile?.contributorActor
        }

        var usesActorProfileAsPrimary: Bool {
            profile?.usesActorProfileAsPrimary ?? false
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
        case performanceButtonTapped(ProgramItem.ID)
    }

    @Feature
    public enum Destination {
        case performanceDetail(Spawn<PerformanceDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

    static func contributorQuery(
        contributorID: Contributor.ID,
        eventID: Event.ID
    ) -> some SelectStatementOf<Contributor> {
        Contributor
            .where { $0.id.eq(contributorID) }
            .where { $0.event.eq(eventID) }
    }

    static func lineupStagesQuery(
        contributorID: Contributor.ID,
        eventID: Event.ID
    ) -> some SelectStatementOf<EventPlace> {
        let placeTable = EventPlace.tableName
        return EventPlace
            .where { $0.event.eq(eventID) }
            .where { _ in
                #sql(
                    """
                    EXISTS (
                      SELECT 1 FROM json_each(
                        json_extract(\(quote: placeTable)."kind", '$.lineup')
                      ) AS "entry"
                      WHERE "entry"."value" = \(contributorID.description)
                    )
                    """,
                    as: Bool.self
                )
            }
            .order { $0.name.collate(.nocase) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                let contributorID = state.contributorID
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editContributor(
                            eventID: eventID,
                            contributorID: contributorID
                        )
                    )
                    await task?.value
                }

            case let .performanceButtonTapped(performanceID):
                guard state.performanceRows.contains(where: { $0.performanceID == performanceID }) else {
                    return
                }
                store.withDependencies {
                    state.destination = .performanceDetail(
                        Spawn(
                            PerformanceDetail.State(
                                performanceID: performanceID,
                                eventID: state.eventID
                            )
                        )
                    )
                }
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
        .onChange(of: store.actorProfileLoadRequest, initial: true) { _, request, _ in
            guard let request else { return }

            store.addTask {
                do {
                    _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                        request.actor.description,
                        24 * 60 * 60,
                        15 * 60
                    )
                } catch is CancellationError {
                } catch {
                }
            }
        }
    }
}

public struct ContributorDetailView: View {
    @Bindable var store: StoreOf<ContributorDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ContributorDetail>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let profile = store.profile,
               let eventTimePresentation = store.state.eventTimePresentation {
                ContributorDetailContentView(
                    profile: profile,
                    heroImageSources: store.heroImageSources,
                    stageContext: store.state.stageContext,
                    performanceRows: store.performanceRows,
                    eventTimePresentation: eventTimePresentation,
                    showsAuthoringControls: showsAuthoringControls,
                    performanceButtonTapped: { performanceID in
                        store.send(.performanceButtonTapped(performanceID))
                    },
                    editButtonTapped: {
                        store.send(.editButtonTapped)
                    }
                )
            } else {
                Group {
                    if showsTechnicalDetails {
                        ContentUnavailableView(
                            "Contributor",
                            systemImage: "person.crop.circle",
                            description: Text(verbatim: store.contributorID.description)
                        )
                    } else {
                        ContentUnavailableView("Contributor unavailable", systemImage: "person.crop.circle")
                    }
                }
                .navigationTitle("Contributor")
            }
        }
        .navigationDestination(item: $store.scope(\.destination).performanceDetail) { detailStore in
            PerformanceDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.contributor-detail.\(store.contributorID.description)"
        )
    }
}
