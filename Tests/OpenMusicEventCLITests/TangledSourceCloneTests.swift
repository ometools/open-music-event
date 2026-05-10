import ArgumentParser
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import Testing

@testable import OpenMusicEventSourceClone

struct TangledSourceCloneTests {
    @Test(arguments: [
        (
            "https://tangled.org/tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "@tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "@tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/did:plc:wshs7t2adsemcrrd4snkeqli/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "did:plc:wshs7t2adsemcrrd4snkeqli",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/tangled.org/core/",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/tangled.org/core.git",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/woody.fm/shambhala-ome",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "woody.fm",
                repository: "shambhala-ome"
            )
        ),
    ])
    func parsesRepositoryReferences(
        rawValue: String,
        expectedReference: TangledRepositoryReference
    ) throws {
        expectNoDifference(
            try TangledRepositoryReference(parsing: rawValue),
            expectedReference
        )
    }

    @Test(arguments: [
        (
            "HEAD",
            "https://tangled.org/tangled.org/core/archive/HEAD.tar.gz"
        ),
        (
            "master",
            "https://tangled.org/tangled.org/core/archive/master.tar.gz"
        ),
        (
            "v1.13.0-alpha",
            "https://tangled.org/tangled.org/core/archive/v1.13.0-alpha.tar.gz"
        ),
        (
            "sl/spindle-rewrite",
            "https://tangled.org/tangled.org/core/archive/sl%2Fspindle-rewrite.tar.gz"
        ),
        (
            "refs/heads/main",
            "https://tangled.org/tangled.org/core/archive/refs%2Fheads%2Fmain.tar.gz"
        ),
    ])
    func buildsArchiveURL(ref: String, expectedURLString: String) throws {
        let repository = try TangledRepositoryReference(parsing: "https://tangled.org/tangled.org/core")

        expectNoDifference(
            try repository.archiveURL(ref: ref).absoluteString,
            expectedURLString
        )
    }

    @Test(arguments: [
        "git@tangled.org:tangled.org/core",
        "ssh://tangled.org/tangled.org/core",
        "file:///tmp/core",
        "tangled.org",
        "tangled.org/core/extra",
    ])
    func rejectsInvalidRepositoryReferences(rawValue: String) {
        do {
            _ = try TangledRepositoryReference(parsing: rawValue)
            Issue.record("Expected repository reference to be rejected: \(rawValue)")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func resolvesTemporaryOutputPathWhenOutputIsOmitted() throws {
        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let expectedURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL

        expectNoDifference(
            TangledSourceCloneCommand.temporaryOutputURL(uuid: uuid),
            expectedURL
        )
    }

    @Test
    func rejectsEmptyOutputPath() {
        do {
            _ = try TangledSourceCloneCommand.resolvedOutputURL("  ")
            Issue.record("Expected empty output path to be rejected.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func rejectsExistingOutputPath() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-existing-output-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
            Issue.record("Expected existing output path to be rejected.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func archiveExtractorExtractsGzippedTarAndFlattensTopLevelDirectory() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Gzipped tar containing repo/event.yml, so the flattening behavior is observable.
        let fixture = try #require(Data(base64Encoded: """
        H4sIAAAAAAAAEytKLcjXZ6AtMDAwMDA3NQXTBgYG6DQWtpm5oRGDgimN3QUGpcUliUUMBgb0sGsQgiJQ/KeWpeaV6FXm5tDGDlCkmpmY4I5/Q2PU+Dc0MDU1YFCgS5yM8PjPS8xNtVIISS0u4Rpop4yCUTAKRsEooCMAAN9H+rQACgAA
        """))

        try TangledSourceArchiveExtractor().extract(fixture, to: outputURL)

        expectNoDifference(
            try String(contentsOf: outputURL.appending(path: "event.yml"), encoding: .utf8),
            "name: Test\n"
        )
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "repo").path()))
    }

    @Test
    func cloneCommandDownloadsExpectedArchivePathWithExplicitOutput() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-clone-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let command = try TangledSourceCloneCommand.parse([
            "@tangled.org/core",
            "--output",
            outputURL.path(),
            "--ref",
            "sl/spindle-rewrite",
        ])

        try await withDependencies {
            $0.httpClient = .testClient { _, path, _ in
                expectNoDifference(
                    path,
                    "/@tangled.org/core/archive/sl%2Fspindle-rewrite.tar.gz"
                )
                return Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { archiveData, output in
                expectNoDifference(archiveData, Data("archive".utf8))
                expectNoDifference(output, outputURL.standardizedFileURL)
            }
        } operation: {
            try await command.run()
        }
    }

    @Test
    func cloneCommandUsesTemporaryOutputWhenOutputIsOmitted() async throws {
        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let expectedOutputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: expectedOutputURL)
        }

        let command = try TangledSourceCloneCommand.parse([
            "https://tangled.org/woody.fm/shambhala-ome",
        ])

        try await withDependencies {
            $0.uuid = .constant(uuid)
            $0.httpClient = .testClient { _, path, _ in
                expectNoDifference(
                    path,
                    "/woody.fm/shambhala-ome/archive/HEAD.tar.gz"
                )
                return Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { archiveData, output in
                expectNoDifference(archiveData, Data("archive".utf8))
                expectNoDifference(output, expectedOutputURL)
            }
        } operation: {
            try await command.run()
        }
    }
}
