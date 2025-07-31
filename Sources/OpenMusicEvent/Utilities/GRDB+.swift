//
//  GRDB+.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/22/25.
//

import Dependencies
import GRDB
import Foundation

public protocol TableDraft:
    EncodableRecord, PersistableRecord, MutablePersistableRecord, TableRecord
{
    associatedtype PrimaryTable: Table
}

public protocol Table: FetchableRecord, TableRecord {
    static var tableName: String { get }
}

public extension Table {
    static var databaseTableName: String {
        Self.tableName
    }
}

public extension TableDraft {
    static var databaseTableName: String {
        self.PrimaryTable.tableName
    }
}

public extension TableDraft where Self: MutableIdentifiable, ID: Numeric {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        self.id = .init(exactly: inserted.rowID)!
    }
}

public protocol MutableIdentifiable: Identifiable {
    var id: ID { get set }
}



extension Organizer: Table {}
extension MusicEvent: Table {}
extension Artist: Table {}
extension Stage: Table {}
extension Schedule: Table {}
extension Performance: Table {}
extension Performance.Artists: Table {}
extension CommunicationChannel: Table {}
extension CommunicationChannel.Post: Table {}
extension Organizer.Draft:  MutableIdentifiable, TableDraft {}
extension MusicEvent.Draft:  MutableIdentifiable, TableDraft {}
extension Artist.Draft:  MutableIdentifiable, TableDraft {}
extension Stage.Draft:  MutableIdentifiable, TableDraft {}
extension Schedule.Draft: MutableIdentifiable, TableDraft {}
extension Performance.Draft:  MutableIdentifiable, TableDraft {}
extension Performance.Artists.Draft:  MutableIdentifiable, TableDraft {}
extension CommunicationChannel.Draft: MutableIdentifiable, TableDraft {}
extension CommunicationChannel.Post.Draft: MutableIdentifiable, TableDraft {}

extension CommunicationChannel.NotificationState: @retroactive FetchableRecord {}

extension TimeZone: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        identifier.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> TimeZone? {
        guard let identifier = String.fromDatabaseValue(dbValue) else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }
}

import Tagged
import GRDB


// Add database support to Tagged values
extension Tagged: @retroactive SQLExpressible where RawValue: SQLExpressible { }
extension Tagged: @retroactive StatementBinding where RawValue: StatementBinding { }
extension Tagged: @retroactive StatementColumnConvertible where RawValue: StatementColumnConvertible { }
extension Tagged: @retroactive DatabaseValueConvertible where RawValue: DatabaseValueConvertible { }


extension ValueObservation {
    public func values(
        scheduling scheduler: some ValueObservationScheduler = .task,
        bufferingPolicy: AsyncValueObservation<Reducer.Value>.BufferingPolicy = .unbounded)
    -> AsyncValueObservation<Reducer.Value>
    where Reducer: ValueReducer
    {
        @Dependency(\.defaultDatabase) var defaultDatabase

        return self.values(in: defaultDatabase, scheduling: scheduler, bufferingPolicy: bufferingPolicy)
    }
}
