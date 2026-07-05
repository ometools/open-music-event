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
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

@Feature
public struct MyEvents {
    public struct State {
        var deleteCreatedEventIDs: [OMERecord.Event.ID] = []
        var destination: Destination.State?
        var errorMessage: String?
        var isDeleteCreatedEventsConfirmationPresented = false
        var organizerDetail: OrganizerDetail.State?
        var sourceDetail: SourceDetail.State?

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.downloadedSourcesQuery)
        var downloadedSources
    }

    public enum Action {
        case deleteCreatedEventsButtonTapped([OMERecord.Event.ID])
        case deleteCreatedEventsConfirmationDeleteButtonTapped
        case deleteCreatedEventsConfirmationPresentedChanged(Bool)
        case didTapCreateEvent
        case didTapDownloadedSource(SourceBaselineRecord.ID)
        case didTapEvent(OMERecord.Event)
        case didTapImportSource
        case didTapOrganizer(OMERecord.Organizer.ID)
        case deleteDownloadedSources([SourceBaselineRecord.ID])
        case destination(Destination.Action)
        case organizerDetail(OrganizerDetail.Action)
        case sourceDetail(SourceDetail.Action)
    }

    static let query = OMERecord.Event.where { event in
        OMERecord.EventOrganizer
            .where { $0.id.organizerID.eq(event.id.organizerID) }
            .where { $0.id.eventID.eq(event.id.eventID) }
            .exists()
            .not()

    }

    static let downloadedSourcesQuery = SourceBaselineRecord
        .group(by: \.id)
        .join(EventSourceProvenanceRecord.all) { $1.sourceBaselineID.eq($0.id) }
        .join(OMERecord.Organizer.all) { $1.id.organizerID.eq($2.id) }
        .order { source, _, _ in
            (source.sourceReference.asc(), source.ref.asc(), source.id.asc())
        }
        .select {
            DownloadedSourceRow.Columns(
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

            case .deleteDownloadedSources(let sourceBaselineIDs):
                store.addTask {
                    do {
                        let sourceProvenances = try database.write { db in
                            var sourceProvenances: [OMERecord.SourceDatabaseInsertion.SourceProvenance] = []
                            for sourceBaselineID in sourceBaselineIDs {
                                let sourceData = try MyEventsDeletion.deleteDownloadedSource(sourceBaselineID, in: db)
                                sourceProvenances.append(contentsOf: sourceData.sourceProvenances)
                            }
                            return sourceProvenances
                        }
                        for sourceProvenance in sourceProvenances {
                            try sourceRepositoryStorage.remove(sourceProvenance)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            if let sourceDetail = $0.sourceDetail,
                               sourceBaselineIDs.contains(sourceDetail.sourceBaselineID) {
                                $0.sourceDetail = nil
                            }
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete source."
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

            case .didTapImportSource:
                state.destination = .sourceImport(Spawn(TangledSourceDownload.State()))

            case .didTapEvent(let event):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(event.id, nil)
                    )
                }

            case .didTapDownloadedSource(let sourceBaselineID):
                store.withDependencies {
                    state.sourceDetail = .init(sourceBaselineID: sourceBaselineID)
                }

            case .didTapOrganizer(let organizerID):
                store.withDependencies {
                    state.organizerDetail = .init(organizerID: organizerID)
                }

            case .destination:
                return

            case .organizerDetail:
                return

            case .sourceDetail:
                return
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.organizerDetail, action: \.organizerDetail) {
            OrganizerDetail()
        }
        .ifLet(\.sourceDetail, action: \.sourceDetail) {
            SourceDetail()
        }
        .onEvent(SourceImportCompleted.self) { importedSource, state in
            state.destination = nil
            store.withDependencies {
                if let sourceBaselineID = importedSource.sourceBaselineID {
                    state.sourceDetail = .init(sourceBaselineID: sourceBaselineID)
                } else {
                    state.organizerDetail = .init(organizerID: importedSource.organizerID)
                }
            }
        }
    }
}

@Selection
public struct DownloadedSourceRow: Equatable, Identifiable, Sendable {
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
