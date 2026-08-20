import ATProto
import ComposableNotificationsServer
import CustomDump
import Dependencies
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import OpenMusicEventLexicon
@testable import OpenMusicEventAppViewServer
import Testing

@Suite(.serialized)
struct SourceArtifactPublicationTests {
    @Test
    func `publication uploads the exact archive to one immutable revision key`() async throws {
        let archiveData = Data("archive".utf8)
        let publishedAt = Date(timeIntervalSince1970: 1_369_353_600)
        let uploads = ArtifactUploadRecorder()
        let publisher = SourceArtifactPublisher.s3(
            configuration: SourceArtifactS3Configuration(
                bucket: "resources.openmusicevent.app",
                region: "us-west-2",
                publicOrigin: try #require(
                    URL(string: "https://resources.openmusicevent.app")
                ),
                credentials: SourceArtifactAWSCredentials(
                    accessKeyID: "AKIDEXAMPLE",
                    secretAccessKey: "fixture-secret-access-key",
                    sessionToken: "fixture-session-token"
                )
            )
        )

        // The publisher receives the validated bytes and exact Tangled revision.
        let artifact = try await withDependencies {
            $0.date = .constant(publishedAt)
            $0.httpClient = HTTPClient { request, body in
                await uploads.record(request: request, body: body)
                return nil
            }
        } operation: {
            try await publisher.publish(
                SourceArtifactPublicationRequest(
                    archiveData: archiveData,
                    repository: Self.artifactRepository,
                    revision: Self.revision
                )
            )
        }

        // The durable publication describes the same bytes at the public repository reference.
        expectNoDifference(
            artifact,
            PublishedSourceArtifact(
                reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
                objectKey: "wickedwoods.ca/ome-workspace/archive/\(Self.revision).tar.gz",
                revision: Self.revision,
                checksumSHA256: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM=",
                byteCount: archiveData.count,
                publishedAt: publishedAt
            )
        )

        // S3 receives one PUT to the revision-owned key, with the exact bytes and integrity fields.
        let recordedUploads = await uploads.snapshot()
        expectNoDifference(recordedUploads.count, 1)
        let upload = try #require(recordedUploads.first)
        expectNoDifference(upload.request.method, .put)
        expectNoDifference(
            upload.request.url?.absoluteString,
            "https://s3.us-west-2.amazonaws.com/resources.openmusicevent.app/wickedwoods.ca/ome-workspace/archive/\(Self.revision).tar.gz"
        )
        expectNoDifference(upload.body, archiveData)
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
            Self.revision
        )
        expectNoDifference(
            upload.request.headerFields[.init("x-amz-security-token")!],
            "fixture-session-token"
        )

        // The authorization covers every S3 header that controls this publication.
        let authorization = try #require(upload.request.headerFields[.authorization])
        #expect(
            authorization.hasPrefix(
                "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20130524/us-west-2/s3/aws4_request"
            )
        )
        #expect(
            authorization.contains(
                "SignedHeaders=cache-control;content-type;host;x-amz-checksum-sha256;x-amz-content-sha256;x-amz-date;x-amz-meta-source-revision;x-amz-security-token"
            )
        )
        #expect(authorization.suffix(64).allSatisfy { $0.isHexDigit })
    }

    @Test
    func `failed publication leaves the source checkpoint empty`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let processor = TangledSourceUpdateProcessor.publishSourceAndNotifyChannels(
            store: store,
            artifactPublisher: SourceArtifactPublisher { _ in
                throw SourceArtifactFixtureError.uploadFailed
            },
            downloadAndValidate: { _, revision in
                Self.validatedArchive(revision: revision)
            }
        )

        // Validation succeeds, but S3 rejects the publication.
        await #expect(throws: SourceArtifactFixtureError.uploadFailed) {
            try await processor.process(Self.update())
        }

        // AppView never advertises a revision whose archive was not published.
        let checkpoint = try await store.tangledSourceCheckpoint(watchID: Self.watchID)
        expectNoDifference(checkpoint, nil)
        let notificationCount = try await database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushOutbox") ?? 0
        }
        expectNoDifference(notificationCount, 0)
    }

    @Test
    func `backfill repairs a legacy checkpoint once and replays without more work`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)

        // This row represents a deployment from before AppView recorded artifact metadata.
        try await database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO tangledSourceRevisions
                      (watchID, repositoryDID, repositoryKey, ref, sourceID, revision)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    Self.watchID.rawValue,
                    Self.repositoryOwnerDID,
                    Self.repositoryKey,
                    "refs/heads/main",
                    Self.canonicalSourceReference,
                    Self.revision,
                ]
            )
        }
        let work = SourceArtifactWorkRecorder()
        let publisher = SourceArtifactPublisher { request in
            await work.recordPublication(request.revision)
            return Self.publishedArtifact(for: request)
        }
        let downloadAndValidate: @Sendable (TangledSourceUpdate, String) async throws
            -> ValidatedSourceArchive = { _, revision in
                await work.recordDownload(revision)
                return Self.validatedArchive(revision: revision)
            }

        // The first run publishes the checkpoint revision and repairs the durable row.
        let firstResults = try await withDependencies {
            $0.date = .constant(Self.receivedAt)
            $0.uuid = .incrementing
        } operation: {
            try await OpenMusicEventAppViewServer.backfillSourceArtifacts(
                watches: [try Self.watch()],
                store: store,
                artifactPublisher: publisher,
                downloadAndValidate: downloadAndValidate
            )
        }

        // A replay reports the same publication without another download or upload.
        let replayedResults = try await withDependencies {
            $0.date = .constant(Self.receivedAt)
            $0.uuid = .incrementing
        } operation: {
            try await OpenMusicEventAppViewServer.backfillSourceArtifacts(
                watches: [try Self.watch()],
                store: store,
                artifactPublisher: publisher,
                downloadAndValidate: downloadAndValidate
            )
        }

        let expectedResult = SourceArtifactBackfillResult(
            watchID: Self.watchID.rawValue,
            revision: Self.revision,
            reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
            objectKey: "wickedwoods.ca/ome-workspace/archive/\(Self.revision).tar.gz",
            checksumSHA256: "fixture-sha256"
        )
        expectNoDifference(firstResults, [expectedResult])
        expectNoDifference(replayedResults, [expectedResult])
        let recordedWork = await work.snapshot()
        expectNoDifference(
            recordedWork,
            SourceArtifactWork(
                downloadedRevisions: [Self.revision],
                publishedRevisions: [Self.revision]
            )
        )

        // The repaired checkpoint is now the catalog's complete publication authority.
        let repairedCheckpoint = try await store.tangledSourceCheckpoint(watchID: Self.watchID)
        let checkpoint = try #require(repairedCheckpoint)
        expectNoDifference(
            checkpoint.publishedArtifact,
            Self.publishedArtifact(
                for: SourceArtifactPublicationRequest(
                    archiveData: Data(Self.revision.utf8),
                    repository: Self.artifactRepository,
                    revision: Self.revision
                )
            )
        )
        let notificationCount = try await database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushOutbox") ?? 0
        }
        expectNoDifference(notificationCount, 0)
    }
}

private extension SourceArtifactPublicationTests {
    static let revision = "2222222222222222222222222222222222222222"
    static let receivedAt = Date(timeIntervalSince1970: 1_786_291_200)
    static let watchID = WebhookInboxDelivery.WatchID(
        rawValue: "staging-owner/festival-staging#refs/heads/main"
    )
    static let repositoryOwnerDID = "did:plc:staging-owner"
    static let repositoryKey = "festival-staging"
    static let canonicalOrganizerID = "did:plc:festival"
    static let canonicalRepositoryRecordKey = "ome"
    static let canonicalSourceReference =
        "at://\(canonicalOrganizerID)/sh.tangled.repo/\(canonicalRepositoryRecordKey)"
    static let artifactRepository = SourceArtifactRepository(
        owner: "wickedwoods.ca",
        repository: "ome-workspace"
    )

    static func update() throws -> TangledSourceUpdate {
        TangledSourceUpdate(
            watchID: watchID,
            deliveryID: .init(rawValue: "d8c7e4a5-48ad-4698-9a95-daee25f36701"),
            repositoryOwnerDID: try #require(DID(repositoryOwnerDID)),
            repositoryKey: .init(rawValue: repositoryKey),
            ref: "refs/heads/main",
            before: String(repeating: "0", count: 40),
            after: revision,
            receivedAt: receivedAt,
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID(canonicalOrganizerID)),
                repositoryRecordKey: .init(rawValue: canonicalRepositoryRecordKey)
            ),
            artifactRepository: artifactRepository
        )
    }

    static func watch() throws -> TangledWebhookWatch {
        TangledWebhookWatch(
            id: watchID,
            hookID: 42,
            repositoryOwnerDID: try #require(DID(repositoryOwnerDID)),
            repositoryKey: .init(rawValue: repositoryKey),
            ref: "refs/heads/main",
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID(canonicalOrganizerID)),
                repositoryRecordKey: .init(rawValue: canonicalRepositoryRecordKey)
            ),
            artifactRepository: artifactRepository
        )
    }

    static func validatedArchive(revision: String) -> ValidatedSourceArchive {
        ValidatedSourceArchive(
            data: Data(revision.utf8),
            snapshot: .empty(revision: revision)
        )
    }

    static func publishedArtifact(
        for request: SourceArtifactPublicationRequest
    ) -> PublishedSourceArtifact {
        PublishedSourceArtifact(
            reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
            objectKey: "wickedwoods.ca/ome-workspace/archive/\(request.revision).tar.gz",
            revision: request.revision,
            checksumSHA256: "fixture-sha256",
            byteCount: request.archiveData.count,
            publishedAt: receivedAt
        )
    }
}

private enum SourceArtifactFixtureError: Error, Equatable {
    case uploadFailed
}

private struct ArtifactUpload: Sendable {
    let request: HTTPRequest
    let body: Data?
}

private actor ArtifactUploadRecorder {
    var uploads: [ArtifactUpload] = []

    func record(request: HTTPRequest, body: Data?) {
        uploads.append(ArtifactUpload(request: request, body: body))
    }

    func snapshot() -> [ArtifactUpload] {
        uploads
    }
}

private struct SourceArtifactWork: Equatable, Sendable {
    var downloadedRevisions: [String] = []
    var publishedRevisions: [String] = []
}

private actor SourceArtifactWorkRecorder {
    var work = SourceArtifactWork()

    func recordDownload(_ revision: String) {
        work.downloadedRevisions.append(revision)
    }

    func recordPublication(_ revision: String) {
        work.publishedRevisions.append(revision)
    }

    func snapshot() -> SourceArtifactWork {
        work
    }
}
