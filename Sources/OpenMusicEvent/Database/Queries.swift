//
//  Queries.swift
//  open-music-event
//
//  Created by Claude on 7/5/25.
//

import GRDB
import CoreModels
import Foundation

struct Queries {
    
    static func fetchPerformances(for artistID: Artist.ID, from db: Database) throws -> [PerformanceDetailRow.ArtistPerformance] {
        let sql = """
            SELECT 
                p.id as id,
                p.stageID as stageID,
                p.startTime as startTime,
                p.endTime as endTime,
                p.title as title,
                s.color as stageColor,
                COALESCE(pp.seen, 0) as isSeen
            FROM performanceArtists pa
            JOIN performances p ON pa.performanceID = p.id
            JOIN stages s ON p.stageID = s.id
            LEFT JOIN performancePreferences pp ON p.id = pp.performanceID
            WHERE pa.artistID = ?
            ORDER BY p.startTime ASC
        """
        
        return try Row.fetchAll(db, sql: sql, arguments: [artistID.rawValue]).map { row in

            return PerformanceDetailRow.ArtistPerformance(
                id: OmeID(row["id"]),
                stageID: OmeID(row["stageID"]),
                startTime: row["startTime"] as Date,
                endTime: row["endTime"] as Date,
                title: row["title"],
                stageColor: OMEColor(rawValue: row["stageColor"]),
                isSeen: row["isSeen"] ?? false
            )
        }
    }
    
    static func fetchPerformanceStages(for artistID: Artist.ID, from db: Database) throws -> [Stage] {
        let sql = """
            SELECT DISTINCT s.id, s.name, s.color, s.musicEventID
            FROM performanceArtists pa
            JOIN performances p ON pa.performanceID = p.id
            JOIN stages s ON p.stageID = s.id
            WHERE pa.artistID = ?
            ORDER BY s.name ASC
        """
        
        return try Row.fetchAll(db, sql: sql, arguments: [artistID.rawValue]).map { row in
            
            Stage(
                id: OmeID(row["id"]),
                musicEventID: OmeID(rawValue: row["musicEventID"]),
                name: row["name"],
                color: OMEColor(rawValue: row["color"])
            )
        }
    }
    
    static func performancesQuery(for stageID: Stage.ID, scheduleID: Schedule.ID) -> QueryInterfaceRequest<Performance> {
        return Performance.filter(
            Column("stageID") == stageID.rawValue &&
            Column("scheduleID") == scheduleID.rawValue
        )
        .order(Column("startTime"))
    }
    
    static func performanceDetailQuery(for performanceID: Performance.ID) -> SQLRequest<PerformanceDetail> {
        return SQLRequest<PerformanceDetail>(
            sql: """
                SELECT 
                    p.id as id,
                    p.title as title,
                    p.stageID as stageID,
                    p.startTime as startTime,
                    p.endTime as endTime,
                    p.performanceRecordings as performanceRecordings,
                    s.color as stageColor,
                    s.name as stageName,
                    s.iconImageURL as stageIconImageURL,
                    COALESCE(pp.seen, 0) as isSeen
                FROM performances p
                JOIN stages s ON p.stageID = s.id
                LEFT JOIN performancePreferences pp ON p.id = pp.performanceID
                WHERE p.id = ?
            """,
            arguments: [performanceID.rawValue]
        )
    }
    
    static func performanceSeenStatusQuery(for performanceID: Performance.ID) -> QueryInterfaceRequest<Performance.Preferences> {
        return Performance.Preferences
            .filter(Column("performanceID") == performanceID.rawValue)
    }
    
    static func performanceArtistsQuery(for performanceID: Performance.ID) -> SQLRequest<Artist> {
        return SQLRequest<Artist>(
            sql: """
                SELECT 
                    a.id as id,
                    a.musicEventID as musicEventID,
                    a.name as name,
                    a.bio as bio,
                    a.imageURL as imageURL,
                    a.links as links
                FROM performanceArtists pa
                JOIN artists a ON pa.artistID = a.id
                WHERE pa.performanceID = ?
                ORDER BY a.name ASC
            """,
            arguments: [performanceID.rawValue]
        )
    }

    static func communicationChannelUserInfoQuery(for musicEventID: MusicEvent.ID) -> SQLRequest<CommunicationChannel.ChannelUserInfo> {
        return SQLRequest<CommunicationChannel.ChannelUserInfo>(
            sql: """
                SELECT 
                    c.id,
                    c.name,
                    c.description,
                    c.notificationsRequired,
                    COALESCE(cp.userNotificationState, c.defaultNotificationState) as userNotificationState
                
                FROM channels c
                LEFT JOIN channelPreferences cp ON c.id = cp.channelID
                WHERE c.musicEventID = ?
                """,
            arguments: [musicEventID]
        )
    }

    static func communicationChannelUserInfoQuery(for channelID: CommunicationChannel.ID) -> SQLRequest<CommunicationChannel.ChannelUserInfo> {
        return SQLRequest<CommunicationChannel.ChannelUserInfo>(
            sql: """
                SELECT 
                    c.id,
                    c.name,
                    c.description,
                    c.notificationsRequired,
                    COALESCE(cp.userNotificationState, c.defaultNotificationState) as userNotificationState
                
                FROM channels c
                LEFT JOIN channelPreferences cp ON c.id = cp.channelID
                WHERE c.channelID = ?
                """,
            arguments: [channelID]
        )
    }
}

