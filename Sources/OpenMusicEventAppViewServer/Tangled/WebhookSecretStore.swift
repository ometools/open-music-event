import Foundation
import GRDB
import SQLiteData

extension OpenMusicEventAppViewStore {
    public func replaceWebhookSecret(
        _ secret: Data,
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID
    ) async throws {
        guard !secret.isEmpty else {
            throw WebhookSecretPersistenceError.emptySecret
        }
        guard let webhookSecretProtection else {
            throw WebhookSecretPersistenceError.protectionUnavailable
        }
        let ciphertext = try webhookSecretProtection.seal(
            secret,
            source: source,
            watchID: watchID
        )
        try await database.write { database in
            try WebhookSecretRow
                .where { $0.source.eq(source.rawValue) }
                .where { $0.watchID.eq(watchID.rawValue) }
                .delete()
                .execute(database)
            try WebhookSecretRow.insert {
                WebhookSecretRow(
                    source: source.rawValue,
                    watchID: watchID.rawValue,
                    secret: ciphertext,
                    secretKeyVersion: webhookSecretProtection.keyVersion
                )
            }
            .execute(database)
        }
    }

    public func webhookSecret(
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID
    ) async throws -> Data? {
        guard let webhookSecretProtection else {
            throw WebhookSecretPersistenceError.protectionUnavailable
        }
        guard let row = try await database.read({ database in
            try WebhookSecretRow
                .where { $0.source.eq(source.rawValue) }
                .where { $0.watchID.eq(watchID.rawValue) }
                .fetchOne(database)
        }) else { return nil }
        return try webhookSecretProtection.open(
            row.secret,
            source: source,
            watchID: watchID,
            keyVersion: row.secretKeyVersion
        )
    }
}

@Table("webhookSecrets")
private struct WebhookSecretRow: Equatable, Sendable {
    var source: String
    var watchID: String
    var secret: Data
    var secretKeyVersion: Int
}

enum WebhookSecretSchema {
    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create webhook secrets") { database in
            let tableName = WebhookSecretRow.tableName
            try #sql(
                """
                    CREATE TABLE \(quote: tableName) (
                      source TEXT NOT NULL,
                      watchID TEXT NOT NULL,
                      secret BLOB NOT NULL,
                      secretKeyVersion INTEGER NOT NULL,
                      PRIMARY KEY (source, watchID)
                    ) STRICT
                    """
            )
            .execute(database)
        }
    }
}
