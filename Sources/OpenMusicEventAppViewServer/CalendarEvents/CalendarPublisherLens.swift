import ATProto
import Foundation
import GRDB
import SQLiteData

struct CalendarPublisherLens: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case allExcept, only }
    var mode: Mode
    var publishers: [Int]

    init(mode: String? = nil, publishers: [Int]? = nil) throws {
        guard let mode = Mode(rawValue: mode ?? "allExcept"),
              (publishers?.count ?? 0) <= 1024,
              publishers?.allSatisfy({ $0 > 0 }) ?? true
        else { throw CalendarBrowseError.invalidParameters }
        self.mode = mode
        self.publishers = Set(publishers ?? []).sorted()
    }

    var fingerprint: String { mode.rawValue + ":" + publishers.map(String.init).joined(separator: ",") }

    func predicate(uri: QueryFragment, catalog: QueryFragment) -> QueryFragment {
        if publishers.isEmpty {
            return mode == .only ? "\(catalog) != \(bind: CalendarPublisher.communityCatalog)" : "1"
        }
        let selected = CalendarPublisherEvent.publisherID.in(publishers)
        let membership: QueryFragment = "EXISTS (SELECT 1 FROM \(CalendarPublisherEvent.self) WHERE \(CalendarPublisherEvent.uri)=\(uri) AND \(selected))"
        return mode == .only
            ? "(\(catalog) != \(CalendarPublisher.communityCatalog) OR \(membership))"
            : "NOT (\(membership))"
    }
}

@Table("calendarPublishers")
struct CalendarPublisher: Codable, Sendable {
    @Column(primaryKey: true) var id: Int
    var did: String
    var label: String?
    var displayName: String? = nil
    var handle: String? = nil
    var avatarURL: String? = nil
    var profileSearch: String = ""
    var profileNextAttempt: Double = 0
    static let communityCatalog = "community.lexicon.calendar.event"
    static let laughTown = "did:plc:k6owgpe2rkkchoiivxhzp2t4"

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Add Community Calendar publisher lens") { db in
            try db.execute(sql: """
                CREATE TABLE "\(tableName)" (id INTEGER PRIMARY KEY AUTOINCREMENT, did TEXT NOT NULL UNIQUE, label TEXT) STRICT;
                INSERT INTO "\(tableName)" (did,label) VALUES ('\(laughTown)','laugh.town');
                CREATE TABLE "\(CalendarPublisherEvent.tableName)" (
                  uri TEXT PRIMARY KEY REFERENCES "\(CalendarEventBrowseProjection.tableName)"(uri) ON DELETE CASCADE,
                  publisherID INTEGER NOT NULL REFERENCES "\(tableName)"(id)) STRICT;
                CREATE INDEX calendar_publisher_events ON "\(CalendarPublisherEvent.tableName)" (publisherID,uri);
                INSERT OR IGNORE INTO "\(tableName)" (did)
                  SELECT DISTINCT substr(uri,6,instr(substr(uri,6),'/')-1)
                  FROM "\(CalendarEventBrowseProjection.tableName)" WHERE catalog='\(communityCatalog)';
                INSERT INTO "\(CalendarPublisherEvent.tableName)" (uri,publisherID)
                  SELECT b.uri,p.id FROM "\(CalendarEventBrowseProjection.tableName)" b
                  JOIN "\(tableName)" p ON p.did=substr(b.uri,6,instr(substr(b.uri,6),'/')-1)
                  WHERE b.catalog='\(communityCatalog)';
                CREATE TRIGGER calendar_publisher_insert AFTER INSERT ON "\(CalendarEventBrowseProjection.tableName)"
                  WHEN NEW.catalog='\(communityCatalog)' BEGIN
                    INSERT OR IGNORE INTO "\(tableName)" (did) VALUES(substr(NEW.uri,6,instr(substr(NEW.uri,6),'/')-1));
                    INSERT INTO "\(CalendarPublisherEvent.tableName)" (uri,publisherID)
                      SELECT NEW.uri,id FROM "\(tableName)" WHERE did=substr(NEW.uri,6,instr(substr(NEW.uri,6),'/')-1);
                END;
                CREATE TABLE "\(CalendarPublisherMapCell.tableName)" (
                  id TEXT PRIMARY KEY NOT NULL,generation INTEGER NOT NULL,depth INTEGER NOT NULL,
                  cell TEXT NOT NULL,publisherID INTEGER NOT NULL,count INTEGER NOT NULL,activeCount INTEGER NOT NULL,
                  x REAL NOT NULL,y REAL NOT NULL,activeX REAL NOT NULL,activeY REAL NOT NULL) STRICT;
                CREATE INDEX calendar_publisher_tiles ON "\(CalendarPublisherMapCell.tableName)" (generation,depth,publisherID,cell);
                CREATE TABLE calendarPublisherBuild (generation INTEGER NOT NULL) STRICT;
                INSERT INTO calendarPublisherBuild SELECT active+1 FROM "\(CalendarMapBuild.tableName)";
                UPDATE "\(CalendarMapBuild.tableName)" SET building=active+1,afterURI=NULL;
                """)
            let add = """
                INSERT INTO "\(CalendarPublisherMapCell.tableName)"
                  (id,generation,depth,cell,publisherID,count,activeCount,x,y,activeX,activeY)
                SELECT NEW.generation||'|'||substr(NEW.cell,1,l.depth)||'|'||p.publisherID,
                  NEW.generation,l.depth,substr(NEW.cell,1,l.depth),p.publisherID,1,NEW.active,
                  NEW.x,NEW.y,NEW.x*NEW.active,NEW.y*NEW.active
                FROM calendarMapLevels l JOIN "\(CalendarPublisherEvent.tableName)" p ON p.uri=NEW.uri
                WHERE NEW.generation >= (SELECT generation FROM calendarPublisherBuild)
                ON CONFLICT(id) DO UPDATE SET count=count+1,activeCount=activeCount+NEW.active,
                  x=x+NEW.x,y=y+NEW.y,activeX=activeX+NEW.x*NEW.active,activeY=activeY+NEW.y*NEW.active;
                """
            let oldIDs = """
                SELECT OLD.generation||'|'||substr(OLD.cell,1,l.depth)||'|'||p.id
                FROM calendarMapLevels l JOIN "\(tableName)" p
                  ON p.did=substr(OLD.uri,6,instr(substr(OLD.uri,6),'/')-1)
                """
            let remove = """
                UPDATE "\(CalendarPublisherMapCell.tableName)" SET count=count-1,activeCount=activeCount-OLD.active,
                  x=x-OLD.x,y=y-OLD.y,activeX=activeX-OLD.x*OLD.active,activeY=activeY-OLD.y*OLD.active
                WHERE id IN (\(oldIDs));
                DELETE FROM "\(CalendarPublisherMapCell.tableName)" WHERE count=0 AND id IN (\(oldIDs));
                """
            try db.execute(sql: """
                CREATE TRIGGER calendar_publisher_map_insert AFTER INSERT ON "\(CalendarMapEvent.tableName)" BEGIN \(add) END;
                CREATE TRIGGER calendar_publisher_map_delete AFTER DELETE ON "\(CalendarMapEvent.tableName)" BEGIN \(remove) END;
                CREATE TRIGGER calendar_publisher_map_update AFTER UPDATE ON "\(CalendarMapEvent.tableName)" BEGIN \(remove) \(add) END;
                """)
        }
    }
}

@Table("calendarPublisherEvents")
struct CalendarPublisherEvent: Codable, Sendable {
    @Column(primaryKey: true) var uri: String
    var publisherID: Int
}

@Table("calendarPublisherMapCells")
struct CalendarPublisherMapCell: Codable, Sendable {
    @Column(primaryKey: true) var id: String
    var generation: Int
    var depth: Int
    var cell: String
    var publisherID: Int
    var count: Int
    var activeCount: Int
    var x: Double
    var y: Double
    var activeX: Double
    var activeY: Double
}

struct CalendarPublishersQuery: XRPC.Query, Sendable {
    static let nsid = ATProto.NSID("app.openmusicevent.calendar.getPublishers")
    typealias Input = Never
    typealias Output = Page
    var parameters: Parameters
    struct Parameters: Codable, Sendable {
        var query: String? = nil
        var cursor: Int? = nil
        var publishers: [Int]? = nil
    }
    struct Page: Codable, Sendable {
        var publishers: [Publisher]
        var cursor: Int?
        var defaults: CalendarPublisherLens
    }
    @Selection struct Publisher: Codable, Sendable {
        var id: Int
        var did: String
        var label: String?
        var handle: String?
        var avatarURL: String?
        var eventCount: Int
    }
}

extension OpenMusicEventAppViewStore {
    @concurrent
    func calendarPublishers(_ parameters: CalendarPublishersQuery.Parameters) async throws -> CalendarPublishersQuery.Page {
        guard (parameters.query?.count ?? 0) <= 256, (parameters.cursor ?? 0) >= 0 else {
            throw CalendarBrowseError.invalidParameters
        }
        let selection = try CalendarPublisherLens(publishers: parameters.publishers)
        return try await database.read { db in
            let defaults = try CalendarPublisher.where { $0.did.in(communityCalendarExcludedPublishers.map(\.description)) }.select(\.id).fetchAll(db)
            let query = (parameters.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let folded = CalendarPublisher.foldProfileSearch(query.hasPrefix("@") ? String(query.dropFirst()) : query)
            let search: QueryFragment = query.isEmpty ? "1" : "(instr(lower(\(CalendarPublisher.did)),lower(\(query)))>0 OR instr(lower(COALESCE(\(CalendarPublisher.label),'')),lower(\(query)))>0 OR instr(\(CalendarPublisher.profileSearch),\(folded))>0)"
            let specified: QueryFragment = parameters.publishers == nil ? "1" : "\(CalendarPublisher.id.in(selection.publishers))"
            let rows = try #sql("""
                WITH ranked AS MATERIALIZED (
                  SELECT \(CalendarPublisher.id) AS id, \(CalendarPublisher.did) AS did,
                    COALESCE(\(CalendarPublisher.displayName),\(CalendarPublisher.label)) AS label,
                    \(CalendarPublisher.handle) AS handle, \(CalendarPublisher.avatarURL) AS avatarURL,
                    (SELECT COUNT(*) FROM \(CalendarPublisherEvent.self)
                     WHERE \(CalendarPublisherEvent.publisherID)=\(CalendarPublisher.id)) AS eventCount,
                    (\(search)) AND (\(specified)) AS matches
                  FROM \(CalendarPublisher.self)
                )
                SELECT id,did,label,handle,avatarURL,eventCount FROM ranked
                WHERE matches AND (\(parameters.cursor ?? 0)=0
                  OR eventCount<(SELECT eventCount FROM ranked WHERE id=\(parameters.cursor ?? 0))
                  OR (eventCount=(SELECT eventCount FROM ranked WHERE id=\(parameters.cursor ?? 0))
                      AND id>\(parameters.cursor ?? 0)))
                ORDER BY eventCount DESC,id ASC LIMIT 51
                """, as: CalendarPublishersQuery.Publisher.self).fetchAll(db)
            return try .init(publishers: Array(rows.prefix(50)),cursor: rows.count>50 ? rows[49].id : nil,
                             defaults: .init(mode: "allExcept", publishers: defaults))
        }
    }
}
