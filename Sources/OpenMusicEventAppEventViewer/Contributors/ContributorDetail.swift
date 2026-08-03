//
//  ContributorDetail.swift
//  open-music-event
//
//  Created by Woodrow Melling on 7/1/26.
//

import ATProto
import BlueskyActorCache
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
import XRPCClient


@Feature
public struct ContributorDetail {
    public init() {}

    public struct State: Identifiable {
        public let contributorID: OMERecord.ID<OMERecord.Contributor>
        public let eventID: OMERecord.Event.ID

        @FetchOne var event: OMERecord.Event?
        @FetchOne var profile: ContributorProfile?

        public init(
            contributorID: OMERecord.ID<OMERecord.Contributor>,
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.contributorID = contributorID
            self.eventID = eventID ?? defaultEventID
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: self.eventID)
            )
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(self.eventID) }
            )
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

        public var id: OMERecord.ID<OMERecord.Contributor> { contributorID }

        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public var destination: Destination.State?
        @FetchAll public var lineupStages: [OMERecord.Stage]
        @FetchAll var performanceRows: [PerformanceRow]

        var contributor: OMERecord.Contributor? {
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

        var contributorActor: OMERecord.Contributor.Actor? {
            profile?.contributorActor
        }

        var usesActorProfileAsPrimary: Bool {
            profile?.usesActorProfileAsPrimary ?? false
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
    }

    @Feature
    public enum Destination {
        case performanceDetail(Spawn<PerformanceDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

    static func contributorQuery(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Contributor> {
        OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.contributorID.eq(contributorID) }
    }

    static func lineupStagesQuery(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        let contributorIDValue = contributorID.rawValue.rawValue
        return OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { _ in
                #sql(
                    """
                    EXISTS (
                      SELECT 1
                      FROM json_each("stages"."lineup")
                      WHERE json_each.value = \(bind: contributorIDValue)
                    )
                    """,
                    as: Bool.self
                )
            }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
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
        .ifLet(\.destination, action: \.destination) {
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
                            description: Text(verbatim: store.contributorID.rawValue.rawValue)
                        )
                    } else {
                        ContentUnavailableView("Contributor unavailable", systemImage: "person.crop.circle")
                    }
                }
                .navigationTitle("Contributor")
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).performanceDetail) { detailStore in
            PerformanceDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
    }
}
