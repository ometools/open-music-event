import Crypto
import Foundation
import GRDB
import SQLiteData

extension OpenMusicEventAppViewStore {
    public func record(
        _ delivery: WebhookInboxDelivery
    ) async throws -> WebhookInboxRecordResult {
        let row = WebhookInboxDeliveryRow(
            source: delivery.source.rawValue,
            watchID: delivery.watchID.rawValue,
            deliveryID: delivery.deliveryID.rawValue,
            event: delivery.event,
            payload: delivery.payload,
            payloadDigest: Data(SHA256.hash(data: delivery.payload)).base64EncodedString(),
            receivedAt: delivery.receivedAt
        )
        return try await database.write { database in
            let existing = try WebhookInboxDeliveryRow
                .where { delivery in delivery.source.eq(row.source) }
                .where { delivery in delivery.deliveryID.eq(row.deliveryID) }
                .fetchOne(database)
            if let existing {
                guard existing.watchID == row.watchID,
                      existing.event == row.event,
                      existing.payloadDigest == row.payloadDigest,
                      existing.payload == row.payload
                else {
                    throw WebhookInboxError.deliveryConflict(
                        source: delivery.source,
                        deliveryID: delivery.deliveryID
                    )
                }
                return .duplicate
            }

            try WebhookInboxDeliveryRow.insert { row }.execute(database)
            return .inserted
        }
    }
}

@Table("webhookInboxDeliveries")
struct WebhookInboxDeliveryRow: Equatable, Sendable {
    var source: String
    var watchID: String
    var deliveryID: String
    var event: String
    var payload: Data
    var payloadDigest: String
    var receivedAt: Date

    var delivery: WebhookInboxDelivery {
        WebhookInboxDelivery(
            source: .init(rawValue: source),
            watchID: .init(rawValue: watchID),
            deliveryID: .init(rawValue: deliveryID),
            event: event,
            payload: payload,
            receivedAt: receivedAt
        )
    }
}

enum WebhookInboxSchema {
    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create webhook inbox deliveries") { database in
            let tableName = WebhookInboxDeliveryRow.tableName
            try #sql(
                """
                    CREATE TABLE \(quote: tableName) (
                      source TEXT NOT NULL,
                      watchID TEXT NOT NULL,
                      deliveryID TEXT NOT NULL,
                      event TEXT NOT NULL,
                      payload BLOB NOT NULL,
                      payloadDigest TEXT NOT NULL,
                      receivedAt TEXT NOT NULL,
                      PRIMARY KEY (source, deliveryID)
                    ) STRICT
                    """
            )
            .execute(database)
        }
    }
}
