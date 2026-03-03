//
//  AppState.swift
//  open-music-event
//
//  Created by Claude on 12/9/24.
//

import Foundation
import GRDB

/// Global app state stored in user preferences database
struct AppState: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appState"

    var id: Int = 1
    var selectedOrganizationID: Organizer.ID?
    var selectedOrganizationURL: URL?

    var selectedEventID: MusicEvent.ID?
}
