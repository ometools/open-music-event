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
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
import Tagged
import SwiftUI
import XRPCClient


@Feature
public struct ContributorDetail {
    public init() {}

    public struct State: Identifiable {
        public let contributorID: OMERecord.ID<OMERecord.Contributor>
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?

        @FetchOne var profile: ContributorProfile?

        public init(
            contributorID: OMERecord.ID<OMERecord.Contributor>,
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID
            @Dependency(\.defaultEventTimeZone) var defaultEventTimeZone

            self.contributorID = contributorID
            self.eventID = eventID ?? defaultEventID
            self.timeZone = defaultEventTimeZone
            _profile = FetchOne(
                ContributorProfile.one(
                    contributorID: contributorID,
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performanceContributors = FetchAll(
                ContributorsViewer.performanceContributorsQuery(eventID: self.eventID)
            )
            _performanceRows = FetchAll(
                PerformanceRow.forContributor(
                    contributorID: contributorID,
                    eventID: self.eventID
                )
            )
            _performances = FetchAll(
                ScheduleViewer.eventPerformancesQuery(eventID: self.eventID)
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: self.eventID)
            )
        }

        public var id: OMERecord.ID<OMERecord.Contributor> { contributorID }

        @DebugSnapshotIgnored public var timeZone: TimeZone
        @FetchAll var performanceRows: [PerformanceRow]
        @FetchAll public var performanceContributors: [OMERecord.Performance.Contributors]
        @FetchAll public var performances: [OMERecord.Performance]
        @FetchAll public var stages: [OMERecord.Stage]

        var contributor: OMERecord.Contributor? {
            profile?.contributor
        }

        var stageContext: ContributorStageContext {
            ContributorStageContext(
                contributorID: contributorID,
                performanceContributors: performanceContributors,
                performances: performances,
                stages: stages
            )
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
    }

    @Feature
    public enum Destination {
        case editContributor(Spawn<EditContributor>)
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

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editContributor(
                        Spawn(
                            EditContributor.State(
                                contributorID: state.contributorID,
                                eventID: state.eventID
                            )
                        )
                    )
                }
            }
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ContributorDetailView: View {
    @Bindable var store: StoreOf<ContributorDetail>

    public init(store: StoreOf<ContributorDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let profile = store.profile {
                ContributorDetailContentView(
                    profile: profile,
                    stageContext: store.state.stageContext,
                    performanceRows: store.performanceRows,
                    timeZone: store.timeZone
                ) {
                    store.send(.editButtonTapped)
                }
            } else {
                ContentUnavailableView(
                    "Contributor",
                    systemImage: "person.crop.circle",
                    description: Text(verbatim: store.contributorID.rawValue.rawValue)
                )
                .navigationTitle("Contributor")
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).editContributor) { editStore in
            NavigationStack {
                EditContributorView(store: editStore)
            }
        }
    }
}
