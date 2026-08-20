import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import HTTPClient
import HTTPTypes
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
@testable import OpenMusicEventAppViewServer
import Testing

@Suite(.serialized)
struct TangledChannelNotificationTests {
    @Test
    func `a staging fork keeps canonical identities for every event in the source`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = directory.appending(path: "source", directoryHint: .isDirectory)
        try Self.writeEvent(
            to: repository,
            eventDirectory: "2026",
            posts: ["gates-open": "The gates are now open."]
        )
        try Self.writeEvent(
            to: repository,
            eventDirectory: "2027",
            posts: ["save-the-date": "See you next year."]
        )

        let checkouts = RequestedCheckouts()
        let checkout = TangledSourceCheckoutClient { request in
            await checkouts.record(request)
            try FileManager.default.copyItem(at: repository, to: request.outputURL)
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }

        let snapshot = try await withDependencies {
            $0.tangledSourceCheckout = checkout
            $0.uuid = .incrementing
        } operation: {
            try await TangledSourceSnapshot.load(
                update: Self.update(
                    before: String(repeating: "0", count: 40),
                    after: Self.afterRevision
                ),
                revision: Self.afterRevision
            )
        }

        expectNoDifference(
            snapshot.posts.map {
                "\($0.id.organizerID)|\($0.id.eventID.rawValue.rawValue)|\($0.id.postID.rawValue.rawValue)"
            },
            [
                "did:plc:festival|ome-2026|gates-open",
                "did:plc:festival|ome-2027|save-the-date",
            ]
        )
        let requestedCheckouts = await checkouts.snapshot()
        expectNoDifference(
            requestedCheckouts,
            [
                RequestedCheckout(
                    repository: "tangled.org/did:plc:staging-owner/festival-staging",
                    ref: Self.afterRevision
                )
            ]
        )
    }

    @Test
    func `a new Tangled post refreshes and alerts only installations subscribed to its channel`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let beforeRepository = directory.appending(path: "before", directoryHint: .isDirectory)
        let afterRepository = directory.appending(path: "after", directoryHint: .isDirectory)
        try Self.writeRepository(
            to: beforeRepository,
            posts: ["welcome": "Welcome to the festival."]
        )
        try Self.writeRepository(
            to: afterRepository,
            posts: [
                "welcome": "Welcome to the festival.",
                "gates-open": "The gates are now open.",
                "parking": "Use the north parking entrance.",
            ]
        )

        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let notifications = withDependencies {
            $0.defaultDatabase = database
            $0.notificationDestinationProtectionClient = protection.client
        } operation: {
            NotificationDatabase()
        }
        try await Self.register(
            id: "development-ios",
            destination: .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "com.Festivl.WickedWoods"),
                    environment: .development,
                    deviceToken: .init(rawValue: "development-device-token")
                )
            ),
            sourceID: .init(rawValue: Self.channelRoute),
            in: notifications
        )
        try await Self.register(
            id: "production-ios",
            destination: .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "com.Festivl.WickedWoods"),
                    environment: .production,
                    deviceToken: .init(rawValue: "production-device-token")
                )
            ),
            sourceID: .init(rawValue: Self.channelRoute),
            in: notifications
        )
        try await Self.register(
            id: "event-only-android",
            destination: .fcm(
                Push.FCM(
                    applicationID: .init(rawValue: "fm.woody.openmusicevent"),
                    installationID: .init(rawValue: "android-installation-id")
                )
            ),
            sourceID: Self.eventSourceID,
            in: notifications
        )

        let update = try Self.update()
        let checkout = TangledSourceCheckoutClient { request in
            let repository: URL
            switch request.ref {
            case Self.beforeRevision:
                repository = beforeRepository
            case Self.afterRevision:
                repository = afterRepository
            default:
                throw FixtureError.unexpectedRevision(request.ref)
            }
            try FileManager.default.copyItem(at: repository, to: request.outputURL)
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: Self.sourceArtifacts,
            load: Self.loadFixtureArchive
        )
        try await withDependencies {
            $0.tangledSourceCheckout = checkout
            $0.uuid = .incrementing
        } operation: {
            try await processor.process(update)
        }

        let firstProjection = try await database.read(Self.persistedProjection)
        expectNoDifference(firstProjection.revision, Self.afterRevision)
        expectNoDifference(firstProjection.postCount, 3)
        expectNoDifference(
            firstProjection.deliveries,
            [
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: "The gates are now open.",
                    kind: "content",
                    route: "\(Self.channelRoute)/posts/gates-open",
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: "gates-open"
                ),
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: "The gates are now open.",
                    kind: "content",
                    route: "\(Self.channelRoute)/posts/gates-open",
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: "gates-open"
                ),
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: "Use the north parking entrance.",
                    kind: "content",
                    route: "\(Self.channelRoute)/posts/parking",
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: "parking"
                ),
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: "Use the north parking entrance.",
                    kind: "content",
                    route: "\(Self.channelRoute)/posts/parking",
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: "parking"
                ),
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: nil,
                    kind: "source_available",
                    route: nil,
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: nil
                ),
                PersistedChannelDelivery(
                    applicationID: "com.Festivl.WickedWoods",
                    body: nil,
                    kind: "source_available",
                    route: nil,
                    sourceID: Self.channelRoute,
                    sourceVersion: Self.afterRevision,
                    title: nil
                ),
            ]
        )

        // A process restart can acknowledge Tangled's replay from the durable checkpoint without
        // checking either revision out again or duplicating either provider job.
        let reopenedStore = try OpenMusicEventAppViewStore(database: database)
        let replayProcessor = TangledSourceUpdateProcessor.channelNotifications(
            store: reopenedStore,
            sourceArtifacts: Self.sourceArtifacts,
            load: Self.loadFixtureArchive
        )
        try await withDependencies {
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                throw FixtureError.unexpectedRevision(request.ref)
            }
            $0.uuid = .incrementing
        } operation: {
            try await replayProcessor.process(update)
        }
        let replayedProjection = try await database.read(Self.persistedProjection)
        expectNoDifference(replayedProjection, firstProjection)
    }

    @Test
    func `the configured AppView projects a signed Tangled webhook into channel deliveries`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let beforeRepository = directory.appending(path: "before", directoryHint: .isDirectory)
        let afterRepository = directory.appending(path: "after", directoryHint: .isDirectory)
        try Self.writeRepository(
            to: beforeRepository,
            posts: ["welcome": "Welcome to the festival."]
        )
        try Self.writeRepository(
            to: afterRepository,
            posts: [
                "welcome": "Welcome to the festival.",
                "gates-open": "The gates are now open.",
            ]
        )

        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(
            database: database,
            webhookSecretProtection: try WebhookSecretProtection(
                keyData: Data(repeating: 0x3B, count: 32)
            )
        )
        try await store.replaceWebhookSecret(
            Self.webhookSecret,
            source: .tangled,
            watchID: .init(rawValue: Self.watchID)
        )
        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let notifications = withDependencies {
            $0.defaultDatabase = database
            $0.notificationDestinationProtectionClient = destinationProtection.client
        } operation: {
            NotificationDatabase()
        }
        try await Self.register(
            id: "wicked-woods-ios",
            destination: .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "com.Festivl.WickedWoods"),
                    environment: .production,
                    deviceToken: .init(rawValue: "production-device-token")
                )
            ),
            sourceID: .init(rawValue: Self.channelRoute),
            in: notifications
        )

        let checkout = TangledSourceCheckoutClient { request in
            let repository: URL
            switch request.ref {
            case Self.beforeRevision:
                repository = beforeRepository
            case Self.afterRevision:
                repository = afterRepository
            default:
                throw FixtureError.unexpectedRevision(request.ref)
            }
            try FileManager.default.copyItem(at: repository, to: request.outputURL)
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
        let payload = Self.webhookPayload()

        try await withDependencies {
            $0.date.now = Self.receivedAt
            $0.tangledSourceCheckout = checkout
            $0.uuid = .incrementing
        } operation: {
            let processor = TangledSourceUpdateProcessor.channelNotifications(
                store: store,
                sourceArtifacts: Self.sourceArtifacts,
                load: Self.loadFixtureArchive
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    tangledWebhook: TangledWebhookConfiguration(
                        watches: [try Self.watch()]
                    )
                ),
                store: store,
                tangledSourceUpdateProcessor: processor
            )
            try await app.test(.router) { client in
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.webhookHeaders(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }
            }
        }

        let inboxCount = try await database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM webhookInboxDeliveries") ?? 0
        }
        expectNoDifference(inboxCount, 1)
        let projection = try await database.read(Self.persistedProjection)
        expectNoDifference(
            projection,
            PersistedProjection(
                revision: Self.afterRevision,
                postCount: 2,
                deliveries: [
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: "The gates are now open.",
                        kind: "content",
                        route: "\(Self.channelRoute)/posts/gates-open",
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.afterRevision,
                        title: "gates-open"
                    ),
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: nil,
                        kind: "source_available",
                        route: nil,
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.afterRevision,
                        title: nil
                    ),
                ]
            )
        )
    }

    @Test
    func `later revisions notify new posts while edits and deletions stay silent`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let beforeRepository = directory.appending(path: "before", directoryHint: .isDirectory)
        let afterRepository = directory.appending(path: "after", directoryHint: .isDirectory)
        let nextRepository = directory.appending(path: "next", directoryHint: .isDirectory)
        try Self.writeRepository(
            to: beforeRepository,
            posts: ["welcome": "Welcome to the festival."]
        )
        try Self.writeRepository(
            to: afterRepository,
            posts: [
                "welcome": "Welcome to the festival.",
                "gates-open": "The gates are now open.",
            ]
        )
        try Self.writeRepository(
            to: nextRepository,
            posts: [
                "welcome": "Welcome to Wicked Woods.",
                "final-call": "The final shuttle leaves at midnight.",
            ]
        )

        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let notifications = withDependencies {
            $0.defaultDatabase = database
            $0.notificationDestinationProtectionClient = protection.client
        } operation: {
            NotificationDatabase()
        }
        try await Self.register(
            id: "wicked-woods-ios",
            destination: .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "com.Festivl.WickedWoods"),
                    environment: .production,
                    deviceToken: .init(rawValue: "production-device-token")
                )
            ),
            sourceID: .init(rawValue: Self.channelRoute),
            in: notifications
        )

        let requestedRevisions = RequestedRevisions()
        let checkout = TangledSourceCheckoutClient { request in
            await requestedRevisions.record(request.ref)
            let repository: URL
            switch request.ref {
            case Self.beforeRevision:
                repository = beforeRepository
            case Self.afterRevision:
                repository = afterRepository
            case Self.nextRevision:
                repository = nextRepository
            default:
                throw FixtureError.unexpectedRevision(request.ref)
            }
            try FileManager.default.copyItem(at: repository, to: request.outputURL)
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: Self.sourceArtifacts,
            load: Self.loadFixtureArchive
        )
        try await withDependencies {
            $0.tangledSourceCheckout = checkout
            $0.uuid = .incrementing
        } operation: {
            try await processor.process(Self.update())
            try await processor.process(
                Self.update(
                    deliveryID: "f486e4c1-8a5f-474c-a8c7-87a6e48b63b3",
                    before: Self.afterRevision,
                    after: Self.nextRevision
                )
            )
        }

        // Once the durable checkpoint exists, AppView only needs the new exact revision. The prior
        // post identities in SQLite are the comparison baseline after a restart.
        let revisions = await requestedRevisions.snapshot()
        expectNoDifference(
            revisions,
            [Self.beforeRevision, Self.afterRevision, Self.nextRevision]
        )
        let projection = try await database.read(Self.persistedProjection)
        expectNoDifference(
            projection,
            PersistedProjection(
                revision: Self.nextRevision,
                postCount: 2,
                deliveries: [
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: "The gates are now open.",
                        kind: "content",
                        route: "\(Self.channelRoute)/posts/gates-open",
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.afterRevision,
                        title: "gates-open"
                    ),
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: nil,
                        kind: "source_available",
                        route: nil,
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.afterRevision,
                        title: nil
                    ),
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: "The final shuttle leaves at midnight.",
                        kind: "content",
                        route: "\(Self.channelRoute)/posts/final-call",
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.nextRevision,
                        title: "final-call"
                    ),
                    PersistedChannelDelivery(
                        applicationID: "com.Festivl.WickedWoods",
                        body: nil,
                        kind: "source_available",
                        route: nil,
                        sourceID: Self.channelRoute,
                        sourceVersion: Self.nextRevision,
                        title: nil
                    ),
                ]
            )
        )
    }

    @Test
    func `revision and watch mismatches preserve the durable projection`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: Self.sourceArtifacts,
            load: { _, revision in
                switch revision {
                case Self.beforeRevision, Self.afterRevision:
                    return ValidatedSourceArchive(
                        data: Data(revision.utf8),
                        snapshot: TangledSourceSnapshot(
                            revision: revision,
                            posts: []
                        )
                    )
                default:
                    throw FixtureError.unexpectedRevision(revision)
                }
            }
        )
        try await processor.process(Self.update())
        let initialProjection = try await database.read(Self.persistedProjection)

        let revisionError = await #expect(throws: OpenMusicEventAppViewStoreError.self) {
            try await processor.process(
                Self.update(
                    deliveryID: "de2d5c7d-d274-455f-b7b0-f89b10d5208e",
                    before: "9999999999999999999999999999999999999999",
                    after: Self.nextRevision
                )
            )
        }
        expectNoDifference(
            revisionError,
            .tangledSourceRevisionMismatch(
                watchID: Self.watchID,
                expected: "9999999999999999999999999999999999999999",
                actual: Self.afterRevision
            )
        )
        let projectionAfterRevisionError = try await database.read(Self.persistedProjection)
        expectNoDifference(projectionAfterRevisionError, initialProjection)

        let watchError = await #expect(throws: OpenMusicEventAppViewStoreError.self) {
            try await processor.process(
                Self.update(
                    deliveryID: "45c89b7e-d727-48e2-b633-8decc7f6d13d",
                    repositoryKey: "other-source",
                    before: Self.afterRevision,
                    after: Self.nextRevision
                )
            )
        }
        expectNoDifference(
            watchError,
            .tangledSourceWatchMismatch(watchID: Self.watchID)
        )
        let projectionAfterWatchError = try await database.read(Self.persistedProjection)
        expectNoDifference(projectionAfterWatchError, initialProjection)
    }

    @Test
    func `a repository creation revision does not attempt to check out the zero before revision`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let requestedRevisions = RequestedRevisions()
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: Self.sourceArtifacts,
            load: { _, revision in
                await requestedRevisions.record(revision)
                guard revision == Self.afterRevision else {
                    throw FixtureError.unexpectedRevision(revision)
                }
                return ValidatedSourceArchive(
                    data: Data(revision.utf8),
                    snapshot: TangledSourceSnapshot(
                        revision: revision,
                        posts: []
                    )
                )
            }
        )
        try await processor.process(
            Self.update(
                before: String(repeating: "0", count: 40),
                after: Self.afterRevision
            )
        )

        let revisions = await requestedRevisions.snapshot()
        expectNoDifference(revisions, [Self.afterRevision])
        let projection = try await database.read(Self.persistedProjection)
        expectNoDifference(
            projection,
            PersistedProjection(
                revision: Self.afterRevision,
                postCount: 0,
                deliveries: []
            )
        )
    }

    @Test
    func `a failed artifact upload cannot advance the source checkpoint`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: SourceArtifactPublisher { _ in
                throw FixtureError.uploadFailed
            },
            load: { _, revision in
                ValidatedSourceArchive(
                    data: Data(revision.utf8),
                    snapshot: TangledSourceSnapshot(
                        revision: revision,
                        eventIDs: [],
                        posts: []
                    )
                )
            }
        )

        await #expect(throws: FixtureError.uploadFailed) {
            try await processor.process(Self.update())
        }
        let checkpoint = try await store.tangledSourceCheckpoint(
            watchID: .init(rawValue: Self.watchID)
        )
        let projection = try await database.read(Self.persistedProjection)
        expectNoDifference(
            checkpoint,
            nil
        )
        expectNoDifference(
            projection,
            PersistedProjection(revision: nil, postCount: 0, deliveries: [])
        )
    }

    @Test
    func `a legacy checkpoint is repaired without duplicating notifications`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try await database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO tangledSourceRevisions
                      (watchID, repositoryDID, repositoryKey, ref, sourceID, revision)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    Self.watchID,
                    Self.repositoryOwnerDID,
                    Self.repositoryKey,
                    "refs/heads/main",
                    "at://\(Self.canonicalOrganizerID)/sh.tangled.repo/\(Self.canonicalRepositoryRecordKey)",
                    Self.afterRevision,
                ]
            )
        }
        let requestedRevisions = RequestedRevisions()
        let publicationRequests = ArtifactPublicationRequests()
        let (results, replayedResults) = try await withDependencies {
            $0.date = .constant(Self.receivedAt)
            $0.uuid = .incrementing
        } operation: {
            let results = try await OpenMusicEventAppViewServer.backfillSourceArtifacts(
                watches: [try Self.watch()],
                store: store,
                sourceArtifacts: SourceArtifactPublisher { request in
                    await publicationRequests.record(request.revision)
                    return Self.publishedArtifact(request: request)
                },
                load: { _, revision in
                    await requestedRevisions.record(revision)
                    return ValidatedSourceArchive(
                        data: Data(revision.utf8),
                        snapshot: TangledSourceSnapshot(
                            revision: revision,
                            eventIDs: [],
                            posts: []
                        )
                    )
                }
            )
            let replayedResults = try await OpenMusicEventAppViewServer
                .backfillSourceArtifacts(
                    watches: [try Self.watch()],
                    store: store,
                    sourceArtifacts: SourceArtifactPublisher { request in
                        await publicationRequests.record(request.revision)
                        return Self.publishedArtifact(request: request)
                    },
                    load: { _, revision in
                        await requestedRevisions.record(revision)
                        return ValidatedSourceArchive(
                            data: Data(revision.utf8),
                            snapshot: TangledSourceSnapshot(
                                revision: revision,
                                eventIDs: [],
                                posts: []
                            )
                        )
                    }
                )
            return (results, replayedResults)
        }

        let revisions = await requestedRevisions.snapshot()
        let publishedRevisions = await publicationRequests.snapshot()
        expectNoDifference(revisions, [Self.afterRevision])
        expectNoDifference(publishedRevisions, [Self.afterRevision])
        let expectedResult = SourceArtifactBackfillResult(
            watchID: Self.watchID,
            revision: Self.afterRevision,
            reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
            objectKey: "wickedwoods.ca/ome-workspace/archive/\(Self.afterRevision).tar.gz",
            checksumSHA256: "fixture-sha256"
        )
        expectNoDifference(results, [expectedResult])
        expectNoDifference(replayedResults, [expectedResult])
        let resolvedCheckpoint = try await store.tangledSourceCheckpoint(
            watchID: .init(rawValue: Self.watchID)
        )
        let checkpoint = try #require(resolvedCheckpoint)
        expectNoDifference(checkpoint.publishedArtifact, Self.publishedArtifact())
        let projection = try await database.read(Self.persistedProjection)
        expectNoDifference(
            projection,
            PersistedProjection(revision: Self.afterRevision, postCount: 0, deliveries: [])
        )
    }

    @Test
    func `the S3 publisher signs and uploads the immutable archive object`() async throws {
        let uploads = ArtifactUploadRequests()
        let publisher = SourceArtifactPublisher.s3(
            configuration: SourceArtifactS3Configuration(
                bucket: "resources.openmusicevent.app",
                region: "us-west-2",
                publicOrigin: try #require(URL(string: "https://resources.openmusicevent.app")),
                credentials: SourceArtifactAWSCredentials(
                    accessKeyID: "AKIDEXAMPLE",
                    secretAccessKey: "fixture-secret-access-key",
                    sessionToken: "fixture-session-token"
                )
            )
        )
        let publishedAt = Date(timeIntervalSince1970: 1_369_353_600)
        let artifact = try await withDependencies {
            $0.date = .constant(publishedAt)
            $0.httpClient = HTTPClient { request, body in
                await uploads.record(request: request, body: body)
                return nil
            }
        } operation: {
            try await publisher.publish(
                SourceArtifactPublicationRequest(
                    archiveData: Data("archive".utf8),
                    repository: Self.artifactRepository,
                    revision: Self.afterRevision
                )
            )
        }

        expectNoDifference(
            artifact,
            PublishedSourceArtifact(
                reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
                objectKey: "wickedwoods.ca/ome-workspace/archive/\(Self.afterRevision).tar.gz",
                revision: Self.afterRevision,
                checksumSHA256: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM=",
                byteCount: 7,
                publishedAt: publishedAt
            )
        )
        let recordedUploads = await uploads.snapshot()
        let upload = try #require(recordedUploads.only)
        expectNoDifference(upload.request.method, .put)
        expectNoDifference(
            upload.request.url?.absoluteString,
            "https://s3.us-west-2.amazonaws.com/resources.openmusicevent.app/wickedwoods.ca/ome-workspace/archive/\(Self.afterRevision).tar.gz"
        )
        expectNoDifference(upload.body, Data("archive".utf8))
        expectNoDifference(
            upload.request.headerFields[.init("x-amz-content-sha256")!],
            "0eb3e36bfb24dcd9bb1d1bece1531216b59539a8fde17ee80224af0653c92aa3"
        )
        expectNoDifference(
            upload.request.headerFields[.init("x-amz-checksum-sha256")!],
            artifact.checksumSHA256
        )
        expectNoDifference(
            upload.request.headerFields[.init("x-amz-meta-source-revision")!],
            Self.afterRevision
        )
        expectNoDifference(
            upload.request.headerFields[.init("x-amz-security-token")!],
            "fixture-session-token"
        )
        let authorization = try #require(upload.request.headerFields[.authorization])
        #expect(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20130524/us-west-2/s3/aws4_request"))
        #expect(authorization.contains("SignedHeaders=cache-control;content-type;host;x-amz-checksum-sha256;x-amz-content-sha256;x-amz-date;x-amz-meta-source-revision;x-amz-security-token"))
        #expect(authorization.suffix(64).allSatisfy { $0.isHexDigit })
    }
}

private extension TangledChannelNotificationTests {
    static let beforeRevision = "1111111111111111111111111111111111111111"
    static let afterRevision = "2222222222222222222222222222222222222222"
    static let nextRevision = "3333333333333333333333333333333333333333"
    static let watchID = "staging-owner/festival-staging#refs/heads/main"
    static let repositoryOwnerDID = "did:plc:staging-owner"
    static let repositoryKey = "festival-staging"
    static let canonicalOrganizerID = "did:plc:festival"
    static let canonicalRepositoryRecordKey = "ome"
    static let channelRoute = "/orgs/did%3Aplc%3Afestival/events/ome-2026/communications/announcements"
    static let receivedAt = Date(timeIntervalSince1970: 1_786_291_200)
    static let webhookSecret = Data("fixture-tangled-secret".utf8)
    static let eventSourceID = NotificationSource.ID(
        rawValue: "at://did:plc:festival/app.openmusicevent.event/ome-2026"
    )

    static func update(
        deliveryID: String = "d8c7e4a5-48ad-4698-9a95-daee25f36701",
        repositoryKey: String = "festival-staging",
        before: String = beforeRevision,
        after: String = afterRevision
    ) throws -> TangledSourceUpdate {
        TangledSourceUpdate(
            watchID: .init(rawValue: watchID),
            deliveryID: .init(rawValue: deliveryID),
            repositoryOwnerDID: try #require(DID(repositoryOwnerDID)),
            repositoryKey: .init(rawValue: repositoryKey),
            ref: "refs/heads/main",
            before: before,
            after: after,
            receivedAt: receivedAt,
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID(canonicalOrganizerID)),
                repositoryRecordKey: .init(rawValue: canonicalRepositoryRecordKey)
            ),
            artifactRepository: Self.artifactRepository
        )
    }

    static func watch() throws -> TangledWebhookWatch {
        TangledWebhookWatch(
            id: .init(rawValue: watchID),
            hookID: 42,
            repositoryOwnerDID: try #require(DID(repositoryOwnerDID)),
            repositoryKey: .init(rawValue: repositoryKey),
            ref: "refs/heads/main",
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID(canonicalOrganizerID)),
                repositoryRecordKey: .init(rawValue: canonicalRepositoryRecordKey)
            ),
            artifactRepository: Self.artifactRepository
        )
    }

    static let artifactRepository = SourceArtifactRepository(
        owner: "wickedwoods.ca",
        repository: "ome-workspace"
    )

    static let sourceArtifacts = SourceArtifactPublisher { request in
        publishedArtifact(request: request)
    }

    static func publishedArtifact(
        request: SourceArtifactPublicationRequest? = nil
    ) -> PublishedSourceArtifact {
        PublishedSourceArtifact(
            reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
            objectKey: "wickedwoods.ca/ome-workspace/archive/\(request?.revision ?? afterRevision).tar.gz",
            revision: request?.revision ?? afterRevision,
            checksumSHA256: "fixture-sha256",
            byteCount: request?.archiveData.count ?? afterRevision.utf8.count,
            publishedAt: receivedAt
        )
    }

    static func loadFixtureArchive(
        update: TangledSourceUpdate,
        revision: String
    ) async throws -> ValidatedSourceArchive {
        ValidatedSourceArchive(
            data: Data(revision.utf8),
            snapshot: try await TangledSourceSnapshot.load(
                update: update,
                revision: revision
            )
        )
    }

    static func webhookPayload() -> Data {
        Data(
            """
            {
              "ref": "refs/heads/main",
              "before": "\(beforeRevision)",
              "after": "\(afterRevision)",
              "repository": {
                "name": "\(repositoryKey)",
                "full_name": "\(repositoryOwnerDID)/\(repositoryKey)",
                "description": "Festival Open Music Event source",
                "fork": false,
                "html_url": "https://tangled.org/\(repositoryOwnerDID)/\(repositoryKey)",
                "clone_url": "https://tangled.org/\(repositoryOwnerDID)/\(repositoryKey)",
                "ssh_url": "git@tangled.org:\(repositoryOwnerDID)/\(repositoryKey)",
                "created_at": "2026-08-01T00:00:00Z",
                "updated_at": "2026-08-16T00:00:00Z",
                "owner": { "did": "\(repositoryOwnerDID)" }
              },
              "pusher": { "did": "\(repositoryOwnerDID)" }
            }
            """.utf8
        )
    }

    static func webhookHeaders(authenticating payload: Data) -> HTTPFields {
        [
            .contentType: "application/json",
            .init("X-Tangled-Event")!: "push",
            .init("X-Tangled-Hook-ID")!: "42",
            .init("X-Tangled-Delivery")!: "d8c7e4a5-48ad-4698-9a95-daee25f36701",
            .init("X-Tangled-Repo")!: "\(repositoryOwnerDID)/\(repositoryKey)",
            .init("X-Tangled-Signature-256")!: TangledWebhookSignature.value(
                authenticating: payload,
                secret: webhookSecret
            ),
        ]
    }

    static func register(
        id: String,
        destination: Push.Destination,
        sourceID: NotificationSource.ID,
        in notifications: NotificationDatabase
    ) async throws {
        let installation = NotificationInstallation(id: .init(rawValue: id))
        try await notifications.insertInstallation(
            installation,
            credentialFingerprint: .init(rawValue: "\(id)-credential")
        )
        try await notifications.replaceDestination(destination, for: installation.id)
        try await notifications.replaceSubscriptions(
            [NotificationSubscription(sourceID: sourceID)],
            for: installation.id
        )
    }

    static func writeRepository(to root: URL, posts: [String: String]) throws {
        try writeEvent(to: root, eventDirectory: "2026", posts: posts)
    }

    static func writeEvent(
        to root: URL,
        eventDirectory: String,
        posts: [String: String]
    ) throws {
        let communications = root
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: eventDirectory, directoryHint: .isDirectory)
            .appending(path: "communications", directoryHint: .isDirectory)
            .appending(path: "announcements", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: communications, withIntermediateDirectories: true)
        try Data(
            """
            name: Festival 2026
            timeZone: America/Denver
            """.utf8
        ).write(
            to: root
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: eventDirectory, directoryHint: .isDirectory)
                .appending(path: "event.yml")
        )
        try Data(
            """
            name: Announcements
            description: Official festival updates.
            defaultNotificationState: subscribed
            """.utf8
        ).write(to: communications.appending(path: "channel-info.yaml"))
        for (postID, contents) in posts {
            try Data(
                """
                ---
                title: \(postID)
                ---
                \(contents)
                """.utf8
            ).write(to: communications.appending(path: "\(postID).md"))
        }
    }

    static func persistedProjection(_ database: Database) throws -> PersistedProjection {
        let revision = try String.fetchOne(
            database,
            sql: "SELECT revision FROM tangledSourceRevisions"
        )
        let postCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM tangledSourceCommunicationPosts"
        ) ?? 0
        let deliveries = try Row.fetchAll(
            database,
            sql: """
                SELECT registrations.applicationID, outbox.message,
                       outbox.sourceID, outbox.sourceVersion
                FROM pushOutbox AS outbox
                JOIN pushRegistrations AS registrations
                  ON registrations.installationID = outbox.installationID
                ORDER BY outbox.sourceVersion, outbox.reason, registrations.applicationID
                """
        )
        .map { row in
            let messageData: Data = row["message"]
            let message = try NotificationProviderMessage(
                json: String(decoding: messageData, as: UTF8.self)
            )
            return PersistedChannelDelivery(
                applicationID: row["applicationID"],
                body: message.data[NotificationProviderMessage.bodyKey],
                kind: message.data[NotificationProviderMessage.kindKey],
                route: message.data[NotificationProviderMessage.routeKey],
                sourceID: row["sourceID"],
                sourceVersion: row["sourceVersion"],
                title: message.data[NotificationProviderMessage.titleKey]
            )
        }
        return PersistedProjection(
            revision: revision,
            postCount: postCount,
            deliveries: deliveries
        )
    }
}

private struct PersistedProjection: Equatable {
    let revision: String?
    let postCount: Int
    let deliveries: [PersistedChannelDelivery]
}

private struct PersistedChannelDelivery: Equatable {
    let applicationID: String
    let body: String?
    let kind: String?
    let route: String?
    let sourceID: String
    let sourceVersion: String
    let title: String?
}

private enum FixtureError: Error, Equatable {
    case uploadFailed
    case unexpectedRevision(String)
}

private struct ArtifactUploadRequest: Sendable {
    let request: HTTPRequest
    let body: Data?
}

private actor ArtifactUploadRequests {
    private var requests: [ArtifactUploadRequest] = []

    func record(request: HTTPRequest, body: Data?) {
        requests.append(ArtifactUploadRequest(request: request, body: body))
    }

    func snapshot() -> [ArtifactUploadRequest] {
        requests
    }
}

private actor ArtifactPublicationRequests {
    private var revisions: [String] = []

    func record(_ revision: String) {
        revisions.append(revision)
    }

    func snapshot() -> [String] {
        revisions
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

private actor RequestedRevisions {
    private var revisions: [String] = []

    func record(_ revision: String) {
        revisions.append(revision)
    }

    func snapshot() -> [String] {
        revisions
    }
}

private struct RequestedCheckout: Equatable, Sendable {
    let repository: String
    let ref: String
}

private actor RequestedCheckouts {
    private var requests: [RequestedCheckout] = []

    func record(_ request: TangledSourceCheckoutRequest) {
        requests.append(
            RequestedCheckout(
                repository: request.repository.normalizedReference,
                ref: request.ref
            )
        )
    }

    func snapshot() -> [RequestedCheckout] {
        requests
    }
}
