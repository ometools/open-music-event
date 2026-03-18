//
//  OrganizerDetails.swift
//  event-viewer
//
//  Created by Woodrow Melling on 3/25/25.
//

import Foundation
import Observation
import  SwiftUI; import SkipFuse
import Dependencies
// import SharingGRDB
import GRDB
import CoreModels
import IssueReporting



struct LoadingScreen: View {
    init(_ text: LocalizedStringKey? = nil) {
        self.text = text
    }
    @Environment(\.loadingScreenImage) var loadingScreenImage

    @State var showingProgressView: Bool = false
    @State var showingLogViewLink: Bool = false
    @State var showingLogView: Bool = false
    var text: LocalizedStringKey?

    var body: some View {
        Group {
            VStack {
                if let image = loadingScreenImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(80)
                }

                if showingProgressView {
                    ProgressView(self.text ?? "Loading")
                }

                if showingLogViewLink {
                    Button("Logs") {
                        self.showingLogView = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        }
        .sheet(isPresented: $showingLogView) {
            NavigationStack {
                LogsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        #if os(Android)
        .background(.black)
        #else
        .background(Material.regular)
        #endif
        .task {
            let delay = 5
            try? await Task.sleep(for: .seconds(delay))
            withAnimation {
                self.showingProgressView = true
            }
            try? await Task.sleep(for: .seconds(delay))
            withAnimation {
                self.showingLogViewLink = true
            }
        }
    }
}

import CasePaths


@Observable
@MainActor
public class OrganizationRoot {
    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "OrganizerDetails")
    typealias Organization = Organizer


    static func openExistingDatabase(for id: Organization.ID) throws -> OrganizationRoot {
        try withDependencies {
            @Dependency(\.organizationDatabaseManager) var orgDatabaseManager
            $0.defaultDatabase = try orgDatabaseManager.openDatabase(id: id)
            
            $0.organizerID = id
        } operation: {
            OrganizationRoot(for: id)
        }

    }

    let id: Organization.ID

    private init(for id: Organization.ID) {
        self.id = id
        _ = Task {
            await self.task()
        }
    }

    var destination: Destination? = nil
    var organization: Organization?

    @CasePathable
    enum Destination {
        case eventViewer(MusicEventViewer)
    }

    func navigate(to route: OrganizationRoute) {
        switch route {
        case .root:
            self.destination = nil
        case .event(let id, let eventRoute):
            withDependencies(from: self) {
                self.destination = .eventViewer(.init(eventID: id))
            }
        }
    }

    public var showingLoadingScreen: Bool = false

    @ObservationIgnored
    @Dependency(\.userPreferencesDatabase) var userPrefsDB

    public func didTapEvent(id: MusicEvent.ID) {
        withErrorReporting {
            try userPrefsDB.write { db in
                var appState = try AppState.fetchOne(db, key: 1) ?? AppState()
                appState.selectedEventID = id
                try appState.save(db)
            }
        }
    }

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database

    func observeOrganizationDetails() async throws {
        logger.info("Observing Organization Details: \(self.id)")
        let query = ValueObservation.tracking { db in
            let organization = try Organizer
                .fetchOne(db)

            let events = try MusicEvent
                .order(Column("startTime").desc)
                .fetchAll(db)

            return (organization, events)
        }

        for try await (organization, events) in query.values(in: self.database) {

            self.events = events
            self.organization = organization
        }
    }


    public func onPullToRefresh() async  {
//            await withErrorReporting {
//                try await downloadAndStoreOrganizer(from: .zipURL(organizer.url))
//            }
    }

    var events: [MusicEvent] = []


    public func task() async {
        logger.info("OrganizationRoot.task")
        await withTaskGroup {
            $0.addTask {
                await withErrorReporting {
                    try await self.observeOrganizationDetails()
                }
            }

            $0.addTask {
                await withErrorReporting {
                    try await self.observeAppState()
                }
            }


            $0.addTask {
                await withDependencies(from: self) {
                    await withErrorReporting {
                        @Dependency(\.resolveOrgID) var resolveOrgID
                        @Dependency(\.downloadAndStoreOrganization) var downloadAndStoreOrganization

                        let reference = try await resolveOrgID(id: self.id)
                        let _ = try await downloadAndStoreOrganization(reference)
                    }
                }
            }

            await $0.waitForAll()
        }
    }

    func observeAppState() async throws {
        logger.log("Observing the AppState")
        let query = ValueObservation.tracking { db in
             try AppState.fetchOne(db)
        }

        for try await appState in query.values(in: database) {
            if let selectedEventID = appState?.selectedEventID {
                if case let .eventViewer(eventViewer) = destination,
                   eventViewer.id == selectedEventID {
                        continue
                } else {
                    withDependencies(from: self) {
                        $0.musicEventID = selectedEventID
                    } operation: {
                        self.destination = .eventViewer(.init(eventID: selectedEventID))
                    }
                }

            } else {
                self.destination = nil
            }
        }
    }

    @ObservationIgnored
    @Dependency(\.date) var date

    var previousEvents: [MusicEvent] {
        events.filter { event in
            if let endTime = event.endTime {
                endTime < date()
            } else {
                true
            }
        }
    }

    var upcomingEvents: [MusicEvent] {
        events.filter { event in
            if let startTime = event.startTime {
                startTime > date()
            } else {
                false
            }
        }
    }

    var currentEvents: [MusicEvent] {
        events.filter { event in
            if let startTime = event.startTime, let endTime = event.endTime {
                startTime < date() && endTime > date()
            } else {
                false
            }
        }
    }
}

public struct OrganizationRootView: View {

    public init(store: OrganizationRoot) {
        self.store = store
    }

    @State var store: OrganizationRoot

    public var body: some View {
        Group {
            if let organizer = store.organization {
                StretchyHeaderList(
                    title: Text(organizer.name),
                    stretchyContent: {
                        OrganizerImageView(organizer: organizer)
                    },
                    listContent: {
                        if !store.currentEvents.isEmpty {
                            Section("Happening Now") {
                                ForEach(store.currentEvents) { event in
                                    NavigationLinkButton {
                                        store.didTapEvent(id: event.id)
                                    } label: {
                                        EventRowView(event: event)
                                    }
                                }
                            }
                        }

                        if !store.upcomingEvents.isEmpty {
                            Section("Upcoming Events") {
                                ForEach(store.upcomingEvents) { event in
                                    NavigationLinkButton {
                                        store.didTapEvent(id: event.id)
                                    } label: {
                                        EventRowView(event: event)
                                    }
                                }
                            }
                        }

                        if !store.previousEvents.isEmpty {
                            Section("Previous Events") {
                                ForEach(store.previousEvents) { event in
                                    NavigationLinkButton {
                                        store.didTapEvent(id: event.id)
                                    } label: {
                                        EventRowView(event: event)
                                    }
                                }
                            }
                        }
                    }
                )
                .transition(.opacity)
                .refreshable { await store.onPullToRefresh() }
                .listStyle(.plain)
            } else {
                VStack {
                    Text("Organization Root View")
                    LoadingScreen()
                }
            }
        }
        .fullScreenCover(item: $store.destination.eventViewer, content: { store in
            MusicEventView(store: store)
        })
        .animation(.default, value: store.destination == nil)
        .task { await store.task() }
    }


    @ViewBuilder
    var organizationDetail: some View {
            }
    struct EventRowView: View {
        var event: MusicEvent

        static let intervalFormatter = {
            let f = DateIntervalFormatter()
            f.dateStyle = .long
            f.timeStyle = .none
            return f
        }()

        var eventDateString: String? {
            if let startTime = event.startTime, let endTime = event.endTime {
                guard startTime <= endTime
                else {
                    reportIssue("Start time (\(String(describing: startTime))) is after end time (\(String(describing: endTime)))")
                    return nil
                }

                return Self.intervalFormatter.string(from: startTime, to: endTime)
            } else if let startTime = event.startTime {
                return startTime.formatted()
            } else {
                return nil
            }
        }

        @Environment(\.databaseDebugInformation) var databaseDebugInfo
        @Environment(\.date) var date

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
                        if databaseDebugInfo.isEnabled {
                            Text(String(event.id.rawValue))
                                .font(.caption2)
    //                            .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .foregroundStyle(.primary)
        }
    }
}

private struct DatabaseDebugInformationKey: EnvironmentKey {
    static let defaultValue = DatabaseDebugStatus.disabled
}

private struct LoadingScreenImageKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

private struct DateKey: EnvironmentKey {
    static let defaultValue: DateGenerator = .init { Date() }
}

public extension EnvironmentValues {
    var databaseDebugInformation: DatabaseDebugStatus {
        get { self[DatabaseDebugInformationKey.self] }
        set { self[DatabaseDebugInformationKey.self] = newValue }
    }
    
    var loadingScreenImage: Image? {
        get { self[LoadingScreenImageKey.self] }
        set { self[LoadingScreenImageKey.self] = newValue }
    }
    
    var date: DateGenerator {
        get { self[DateKey.self] }
        set { self[DateKey.self] = newValue }
    }
}

public enum DatabaseDebugStatus: Sendable {
    case enabled
    case disabled

    var isEnabled: Bool {
        self == .enabled
    }
}

// import Sharing
// TODO: Replace SharedKey extension with proper state management
// extension SharedKey where Self == AppStorageKey<MusicEvent.ID?> {
//     static var eventID: Self {
//         .appStorage("OME-eventID")
//     }
// }

enum Current {
    static var musicEvent: QueryInterfaceRequest<MusicEvent> {
        @Dependency(\.musicEventID) var musicEventID
        return MusicEvent.filter(id: musicEventID)
    }

//    static var organizer: QueryInterfaceRequest<Organizer> {
//        @Dependency(\.musicEventID) var musicEventID
//        return Organizer.joining(required: Organizer.musicEvents.filter(id: musicEventID))
//    }

    static var artists: QueryInterfaceRequest<Artist> {
        @Dependency(\.musicEventID) var musicEventID
        return Artist.filter(Column("musicEventID") == musicEventID)
    }

    static var stages: QueryInterfaceRequest<Stage> {
        @Dependency(\.musicEventID) var musicEventID
        return Stage
            .filter(Column("musicEventID") == musicEventID)
            .order(Column("sortIndex"))
    }

    static var schedules: QueryInterfaceRequest<Schedule> {
        @Dependency(\.musicEventID) var musicEventID
        return Schedule
            .filter(Column("musicEventID") == musicEventID)
            .order(Column("startTime"))
    }
    
    static var posters: QueryInterfaceRequest<Poster> {
        @Dependency(\.musicEventID) var musicEventID

        return Poster
            .filter(Column("musicEventID") == musicEventID)
            .order(Column("sortIndex"))
    }
    
//    static var performances: QueryInterfaceRequest<Performance> {
//        @Dependency(\.musicEventID) var musicEventID
//        return Performance
//            .joining(required: Performance.stage.filter(Column("musicEventID") == musicEventID))
//    }
}



let intervalFormatter = DateIntervalFormatter()



//#Preview {
//    prepareDependencies {
//        try! $0.defaultDatabase = appDatabase()
//    }
//
//    OrganizerDetailView(url: .init("")!)
//        .environment(\.loadingScreenImage, Image("WWVector", bundle: .module))
//}



extension Organizer {
    static let placeholder = Organizer.omeTools
}

