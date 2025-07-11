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
                s.color as stageColor
            FROM performanceArtists pa
            JOIN performances p ON pa.performanceID = p.id
            JOIN stages s ON p.stageID = s.id
            WHERE pa.artistID = ?
            ORDER BY p.startTime ASC
        """
        
        return try Row.fetchAll(db, sql: sql, arguments: [artistID.rawValue]).map { row in
            let startTimeString: String = row["startTime"]
            let endTimeString: String = row["endTime"]
            
            return PerformanceDetailRow.ArtistPerformance(
                id: OmeID(row["id"]),
                stageID: OmeID(row["stageID"]),
                startTime: ISO8601DateFormatter().date(from: startTimeString) ?? Date(),
                endTime: ISO8601DateFormatter().date(from: endTimeString) ?? Date(),
                title: row["title"],
                stageColor: OMEColor(rawValue: row["stageColor"])
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
                    s.color as stageColor,
                    s.name as stageName,
                    s.iconImageURL as stageImageURL
                FROM performances p
                JOIN stages s ON p.stageID = s.id
                WHERE p.id = ?
            """,
            arguments: [performanceID.rawValue]
        )
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
}

