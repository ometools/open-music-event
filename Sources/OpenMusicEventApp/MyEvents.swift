//
//  MyEvents.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

struct FetchLoadFailure: Identifiable {
    var id: String { label }

    var label: String
    var error: any Error

    init?(
        label: String,
        error: (any Error)?
    ) {
        guard let error else { return nil }
        self.label = label
        self.error = error
    }
}

@Feature
public struct MyEvents {
    public typealias TeamWorkspace = OpenMusicEventAuthoring<TeamWorkspaceDetail>

    public struct State {
        var deleteCreatedEventIDs: [OMERecord.Event.ID] = []
        var destination: Destination.State?
        var errorMessage: String?
        var isDeleteCreatedEventsConfirmationPresented = false
        var organizerDetail: OrganizerDetail.State?
        var teamWorkspaceDetail: TeamWorkspace.State?

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.teamWorkspacesQuery)
        var teamWorkspaces

        var fetchLoadFailures: [FetchLoadFailure] {
            [
                FetchLoadFailure(label: "MyEvents.events", error: $events.loadError),
                FetchLoadFailure(label: "MyEvents.teamWorkspaces", error: $teamWorkspaces.loadError),
            ]
            .compactMap { $0 }
        }

    }

    public enum Action {
        case deleteCreatedEventsButtonTapped([OMERecord.Event.ID])
        case deleteCreatedEventsConfirmationDeleteButtonTapped
        case deleteCreatedEventsConfirmationPresentedChanged(Bool)
        case didTapCreateEvent
        case didTapTeamWorkspace(SourceBaselineRecord.ID)
        case didTapEvent(OMERecord.Event)
        case didTapImportTeamWorkspace
        case didTapOrganizer(OMERecord.Organizer.ID)
        case deleteTeamWorkspaces([SourceBaselineRecord.ID])
        case destination(Destination.Action)
        case organizerDetail(OrganizerDetail.Action)
        case teamWorkspaceDetail(TeamWorkspace.Action)
    }

    static let query = OMERecord.Event.where { event in
        OMERecord.EventOrganizer
            .where { $0.id.organizerID.eq(event.id.organizerID) }
            .where { $0.id.eventID.eq(event.id.eventID) }
            .exists()
            .not()

    }

    static let teamWorkspacesQuery = SourceBaselineRecord
        .group(by: \.id)
        .join(EventSourceProvenanceRecord.all) { $1.sourceBaselineID.eq($0.id) }
        .join(OMERecord.Organizer.all) { $1.id.organizerID.eq($2.id) }
        .order { source, _, _ in
            (source.sourceReference.asc(), source.ref.asc(), source.id.asc())
        }
        .select {
            TeamWorkspaceRow.Columns(
                sourceBaseline: $0,
                organizer: $2,
                eventCount: $1.sourceEventDirectory.count()
            )
        }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
        case sourceImport(Spawn<TangledSourceDownload>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case let .deleteCreatedEventsButtonTapped(eventIDs):
                let eventIDs = eventIDs.uniqued()
                guard !eventIDs.isEmpty else { return }
                state.deleteCreatedEventIDs = eventIDs
                state.isDeleteCreatedEventsConfirmationPresented = true

            case .deleteTeamWorkspaces(let sourceBaselineIDs):
                store.addTask {
                    do {
                        let sourceProvenances = try database.write { db in
                            var sourceProvenances: [OMERecord.SourceDatabaseInsertion.SourceProvenance] = []
                            for sourceBaselineID in sourceBaselineIDs {
                                let sourceData = try MyEventsDeletion.deleteTeamWorkspace(sourceBaselineID, in: db)
                                sourceProvenances.append(contentsOf: sourceData.sourceProvenances)
                            }
                            return sourceProvenances
                        }
                        for sourceProvenance in sourceProvenances {
                            try sourceRepositoryStorage.remove(sourceProvenance)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            if let teamWorkspaceDetail = $0.teamWorkspaceDetail,
                               sourceBaselineIDs.contains(
                                   teamWorkspaceDetail.content.content.sourceBaselineID
                               ) {
                                $0.teamWorkspaceDetail = nil
                            }
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete shared workspace."
                        }
                    }
                }

            case .deleteCreatedEventsConfirmationDeleteButtonTapped:
                let eventIDs = state.deleteCreatedEventIDs
                store.addTask {
                    do {
                        try database.write { db in
                            try MyEventsDeletion.deleteCreatedLocalEvents(eventIDs, in: db)
                        }
                        try store.modify {
                            $0.deleteCreatedEventIDs = []
                            $0.errorMessage = nil
                            $0.isDeleteCreatedEventsConfirmationPresented = false
                        }
                    } catch {
                        try store.modify {
                            $0.isDeleteCreatedEventsConfirmationPresented = false
                            $0.errorMessage = "Unable to delete event."
                        }
                    }
                }

            case let .deleteCreatedEventsConfirmationPresentedChanged(isPresented):
                state.isDeleteCreatedEventsConfirmationPresented = isPresented
                if !isPresented {
                    state.deleteCreatedEventIDs = []
                }

            case .didTapCreateEvent:
                state.destination = .createEvent(Spawn(CreateEvent.State()))

            case .didTapImportTeamWorkspace:
                state.destination = .sourceImport(Spawn(TangledSourceDownload.State()))

            case .didTapEvent(let event):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(event.id, nil)
                    )
                }

            case .didTapTeamWorkspace(let sourceBaselineID):
                store.withDependencies {
                    state.openTeamWorkspace(sourceBaselineID)
                }

            case .didTapOrganizer(let organizerID):
                store.withDependencies {
                    state.organizerDetail = .init(organizerID: organizerID)
                }

            case .destination:
                return

            case .organizerDetail:
                return

            case .teamWorkspaceDetail:
                return
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.organizerDetail, action: \.organizerDetail) {
            OrganizerDetail()
        }
        .ifLet(\.teamWorkspaceDetail, action: \.teamWorkspaceDetail) {
            TeamWorkspace(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventSourceEditing.Authoring {
                    TeamWorkspaceDetail()
                }
            }
            .invalidatingAuthoringWhenAuthorizationIsLost()
        }
        .onEvent(SourceImportCompleted.self) { importedSource, state in
            state.destination = nil
            store.withDependencies {
                if let sourceBaselineID = importedSource.sourceBaselineID {
                    state.openTeamWorkspace(sourceBaselineID)
                } else {
                    state.organizerDetail = .init(organizerID: importedSource.organizerID)
                }
            }
        }
        .onEvent(TangledWorkspaceBootstrapCompleted.self) { result, state in
            store.withDependencies {
                state.openTeamWorkspace(result.sourceBaselineID)
            }
        }
    }
}

private extension MyEvents.State {
    mutating func openTeamWorkspace(_ sourceBaselineID: SourceBaselineRecord.ID) {
        teamWorkspaceDetail = MyEvents.TeamWorkspace.State(
            storage: OpenMusicEventOAuth.storage
        ) {
            OpenMusicEventSourceEditing.Authoring<TeamWorkspaceDetail>.State(
                workspaceID: EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
            ) {
                TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
            }
        }
    }
}

@Selection
public struct TeamWorkspaceRow: Equatable, Identifiable, Sendable {
    public var sourceBaseline: SourceBaselineRecord
    public var organizer: OMERecord.Organizer
    public var eventCount: Int

    public var id: SourceBaselineRecord.ID {
        sourceBaseline.id
    }

    public var refTitle: String {
        sourceBaseline.ref ?? "default ref"
    }
}
