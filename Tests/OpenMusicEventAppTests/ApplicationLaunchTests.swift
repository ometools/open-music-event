//
//  FirstRunEndToEndTests.swift
//  open-music-event
//
//  Created by Woodrow Melling on 3/21/26.
//


import Testing
import GRDB
import Dependencies
@testable import OpenMusicEvent
import Foundation


extension DownloadAndStoreOrganizationClient {
    static func fetchNeeded(duration: Duration = .seconds(0)) -> Self {
        .init { reference in
            try? await Task.sleep(for: .seconds(2))
            let id = Organizer.ID("testival")
            // Open/create the per-org database we want to write into
            @Dependency(\.organizationDatabaseManager) var dbManager
            let perOrgDB = try dbManager.openDatabase(id: id)

            // Insert minimal Organizer + one MusicEvent so observations fire
            try await perOrgDB.write { db in
                let organizer = Organizer.Draft(
                    id: id,
                    url: URL(string: "https://openmusicevent.app/orgs/testival")!,
                    name: "testival",
                    imageURL: nil,
                    iconImageURL: nil
                )
                try organizer.upsert(db)

                let eventID: MusicEvent.ID = .init(rawValue: "\(id)/event-1")
                let event = MusicEvent.Draft(
                    id: eventID,
                    organizerID: id,
                    name: "Opening Event",
                    timeZone: .current,
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    location: nil,
                    contactNumbers: []
                )
                try event.upsert(db)
            }
        }
    }
}

@MainActor
@Suite
struct ApplicationLaunchTests {

    init() {
        withErrorReporting {
            try prepareDependencies { _ in
                try OME.prepareDependencies(enableFirebase: false)
            }
        }
    }

    @Test(
        .dependency(\.downloadAndStoreOrganization, .fetchNeeded()),
        .dependency(\.resolveOrgID, .init { _ in .zipURL(URL(string: "https://openmusicevent.app/data/testival")!) } )
    )
    func `deep link downloads, stores, and navigates to the correct organization root`() async throws {
        let url = URL(string: "https://openmusicevent.app/orgs/testival")!
        
        // Prepare dependencies for test run
        // Create app model and navigate to the parsed route
        let model = OMEAppEntryPoint.Model()

        model.didReceiveURL(url: url)

        // Ensure the selection was persisted
        @Dependency(\.userPreferencesDatabase) var userPrefsDB
        let appState = try await userPrefsDB.read { db in try AppState.fetchOne(db) }
        #expect(appState?.selectedOrganizationID == "testival")

        let root = try #require(model.organizationRoot)


//
//        // Attach the observation on organization details
//        let observeTask = Task {
//            try await root.observeOrganizationDetails()
//        }
//
//        // Trigger the real download/store (your production function)
//        // Adjust reference if you have a different resolver
//        let reference = OrganizationReference.repository(
//            .init(
//                baseURL: URL(string: "https://github.com/wicked-woods/wicked-woods-ome")!,
//                version: .branch("main")
//            )
//        )

//        // Use the real V2 that writes into the per-org DB
//        let dbQueue = try await downloadAndStoreOrganizationV2(from: reference)
//        _ = dbQueue // Just to silence warnings if unused
//
//        // Give the observation time to process the initial write
//        try await Task.sleep(for: .milliseconds(400))
//
//        // Assert that OrganizationRoot has updated on the very first write
//        #expect(root.organization?.id == "wicked-woods")
//        #expect(!root.events.isEmpty)
//
//        observeTask.cancel()
    }

    @Test(
        .dependency(\.downloadAndStoreOrganization, .fetchNeeded(duration: .seconds(0.1))),
        .dependency(\.resolveOrgID, .init { _ in .zipURL(URL(string: "https://openmusicevent.app/data/testival")!) } )
    )
    func `deep link slowly downloads, stores, and navigates to the correct organization root`() async throws {
        let url = URL(string: "https://openmusicevent.app/orgs/testival")!

        // Prepare dependencies for test run
        // Create app model and navigate to the parsed route
        let model = OMEAppEntryPoint.Model()

        model.didReceiveURL(url: url)

        // Ensure the selection was persisted
        @Dependency(\.userPreferencesDatabase) var userPrefsDB
        let appState = try await userPrefsDB.read { db in try AppState.fetchOne(db) }
        #expect(appState?.selectedOrganizationID == "testival")

        try? await Task.sleep(for: .seconds(1))
        let root = try #require(model.organizationRoot)
    }
}
