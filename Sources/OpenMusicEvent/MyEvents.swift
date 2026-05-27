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
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct MyEvents {
    public struct State {
        var destination: Destination.State?
        var errorMessage: String?
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
            case .deleteDownloadedSources(let sourceBaselineIDs):
                store.addTask {
                    do {
                        let sourceProvenances = try database.write { db in
                            var sourceProvenances: [OMERecord.SourceDatabaseInsertion.SourceProvenance] = []
                            for sourceBaselineID in sourceBaselineIDs {
                                let sourceData = try deleteDownloadedSource(sourceBaselineID, in: db)
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

private func deleteDownloadedSource(
    _ sourceBaselineID: SourceBaselineRecord.ID,
    in db: Database
) throws -> OMERecord.DeletedOrganizerSourceData {
    let sourceData = try OMERecord.deleteDownloadedSourceData(
        for: sourceBaselineID,
        in: db
    )
    let eventIDs = sourceData.eventIDs
    let appState = try AppState.find(1).fetchOne(db)
    if let selectedEventID = appState?.selectedEventID,
       eventIDs.contains(selectedEventID) {
        try AppState.update {
            $0.organizerID = #bind(nil as OMERecord.Organizer.ID?)
            $0.eventID = #bind(nil as OMERecord.ID<OMERecord.Event>?)
        }
        .execute(db)
    }

    try deleteEventOwnedRecords(eventIDs, in: db)
    try deleteUnreferencedOrganizers(eventIDs.map(\.organizerID), in: db)
    return sourceData
}

private func deleteEventOwnedRecords(
    _ eventIDs: [OMERecord.Event.ID],
    in db: Database
) throws {
    for eventID in eventIDs.uniqued() {
        try OMERecord.Performance.Participants
            .where { $0.organizerID.eq(eventID.organizerID) }
            .where { $0.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Channel
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Participant.Claim
            .where { $0.participantID.organizerID.eq(eventID.organizerID) }
            .where { $0.participantID.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Schedule
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.EventOrganizer
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try OMERecord.Event
            .where { $0.id.eq(eventID) }
            .delete()
            .execute(db)

        try EventViewerState
            .where { $0.id.eq(eventID) }
            .delete()
            .execute(db)
        try ScheduleViewerState
            .where { $0.id.eventID.eq(eventID) }
            .delete()
            .execute(db)
        try ParticipantPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try PerformancePreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try ChannelPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try PosterPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
        try LocalImageBlob
            .where { $0.organizerID.eq(eventID.organizerID) }
            .where { $0.eventID.eq(eventID.eventID) }
            .delete()
            .execute(db)
    }
}

private func deleteUnreferencedOrganizers(
    _ organizerIDs: [OMERecord.Organizer.ID],
    in db: Database
) throws {
    for organizerID in organizerIDs.uniqued() {
        let eventOrganizerCount = try OMERecord.EventOrganizer
            .where { $0.id.eventOrganizerID.eq(organizerID) }
            .fetchCount(db)
        let ownedEventCount = try OMERecord.Event
            .where { $0.id.organizerID.eq(organizerID) }
            .fetchCount(db)
        if eventOrganizerCount == 0 && ownedEventCount == 0 {
            try OrganizerPreferences
                .where { $0.organizerID.eq(organizerID) }
                .delete()
                .execute(db)
            try OMERecord.Organizer
                .where { $0.id.eq(organizerID) }
                .delete()
                .execute(db)
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        var result: [Element] = []
        for element in self where seen.insert(element).inserted {
            result.append(element)
        }
        return result
    }
}

struct MyEventsView: View {
    @Bindable var store: StoreOf<MyEvents>

    var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !store.downloadedSources.isEmpty {
                Section("Downloaded Sources") {
                    ForEach(store.downloadedSources) { downloadedSource in
                        Button {
                            store.send(.didTapDownloadedSource(downloadedSource.id))
                        } label: {
                            DownloadedSourceRowView(downloadedSource: downloadedSource)
                        }
                    }
                    .onDelete { offsets in
                        deleteDownloadedSources(at: offsets)
                    }
                }
            }

            if !store.events.isEmpty {
                Section("Events") {
                    ForEach(store.events) { event in
                        Button {
                            store.send(.didTapEvent(event))
                        } label: {
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Events")
        .listStyle(.plain)
        .toolbar {
            Button("Import Source", systemImage: "arrow.down.doc") {
                store.send(.didTapImportSource)
            }

            Button("Create Event", systemImage: "plus") {
                store.send(.didTapCreateEvent)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                CreateEventView(store: createEventStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).sourceImport) { downloadStore in
            NavigationStack {
                TangledSourceDownloadView(store: downloadStore)
                    .openMusicEventAuthorizationDestination(
                        store: downloadStore.scope(\.authorization, action: \.authorization)
                    )
            }
        }
        .navigationDestination(item: $store.scope(\.organizerDetail, action: \.organizerDetail)) { detailStore in
            OrganizerDetailView(store: detailStore)
        }
        .navigationDestination(item: $store.scope(\.sourceDetail, action: \.sourceDetail)) { detailStore in
            SourceDetailView(store: detailStore)
        }
    }

    func deleteDownloadedSources(at offsets: IndexSet) {
        let sourceBaselineIDs = offsets.compactMap { offset in
            store.downloadedSources.indices.contains(offset)
                ? store.downloadedSources[offset].id
                : nil
        }
        store.send(.deleteDownloadedSources(sourceBaselineIDs))
    }
}

#Preview {
    NavigationStack {
        MyEventsView(store: Store(initialState: .init(), feature: {
            MyEvents()
        }))
    }
}

import SwiftUI

struct OrganizerRowView: View {
    var organizer: OMERecord.Organizer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            Text(organizer.id.description)
                .lineLimit(1)

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct DownloadedSourceRowView: View {
    var downloadedSource: DownloadedSourceRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(downloadedSource.sourceBaseline.sourceReference)
                    .lineLimit(1)
                Text(
                    "\(downloadedSource.refTitle) - \(downloadedSource.organizer.id.description)"
                )
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct EventRowView: View {
    var event: OMERecord.Event
    
    var eventDateString: String? {
        event.eventDateText(dateStyle: .long)
    }

    var body: some View {
        HStack(spacing: 10) {
            EventIconImageView(event: event)
                .frame(width: 60, height: 60)
            //                    .foregroundColor(.label)
            //                .invertForLightMode()

            HStack {
                VStack(alignment: .leading) {
                    Text(event.name)
                    if let eventDateString {
                        Text(eventDateString)
                            .lineLimit(1)
                            .font(.caption2)
                    }
                }
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }


    struct EventIconImageView: View {
        let event: OMERecord.Event
        var body: some View {

        }
    }
}

private extension OMERecord.Event {
    func eventDateText(dateStyle: DateFormatter.Style) -> String? {
        switch (startDate, endDate) {
        case let (.some(startDate), .some(endDate)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(
                from: startDate.atStartOfDay(in: timeZone),
                to: endDate.atStartOfDay(in: timeZone)
            )

        case let (.some(startDate), .none):
            return startDate.formatted(dateStyle: dateStyle, in: timeZone)

        case let (.none, .some(endDate)):
            return endDate.formatted(dateStyle: dateStyle, in: timeZone)

        case (.none, .none):
            return nil
        }
    }
}

private extension LocalDate {
    func formatted(dateStyle: DateFormatter.Style, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}
