import CustomDump
import Dependencies
import Foundation
import SourceEditing
import Testing

struct SourcePatchPublisherTests {
    @Test
    func preparedWorkingTreeAppliesPatchAndKeepsTemporaryCheckout() async throws {
        let fixture = try SourcePatchPublisherFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        try fixture.writeFile("events/test/unchanged.md", contents: "Same\n")
        let repositoryURL = fixture.repositoryURL
        let rootURL = fixture.rootURL

        let publication = try await withDependencies {
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: rootURL
            )
        } operation: {
            try await SourcePatchPublisher.preparedWorkingTree.publish(
                SourcePatchPublishRequest(
                    location: SourcePatchLocation(
                        repositoryURL: repositoryURL,
                        relativePath: "events/test"
                    ),
                    patch: SourcePatch(
                        fileChanges: [
                            SourcePatchFileChange(
                                path: "events/test/added.md",
                                kind: .added,
                                newContents: data("Added\n")
                            ),
                            SourcePatchFileChange(
                                path: "events/test/event.yml",
                                kind: .modified,
                                oldContents: data("name: Old\n"),
                                newContents: data("name: New\n")
                            ),
                        ]
                    )
                )
            )
        }

        expectNoDifference(publication.sourceChangeURL, nil)
        let workingTree = try #require(publication.workingTree)
        defer { try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL) }
        expectNoDifference(workingTree.originalRepositoryURL, repositoryURL.standardizedFileURL)
        expectNoDifference(workingTree.relativePath, "events/test")
        #expect(workingTree.workingRepositoryURL != repositoryURL)
        expectNoDifference(
            try String(
                contentsOf: workingTree.workingRepositoryURL.appending(path: "events/test/event.yml"),
                encoding: .utf8
            ),
            "name: New\n"
        )
        expectNoDifference(
            try String(
                contentsOf: workingTree.workingRepositoryURL.appending(path: "events/test/added.md"),
                encoding: .utf8
            ),
            "Added\n"
        )
        expectNoDifference(
            try String(
                contentsOf: workingTree.workingRepositoryURL.appending(path: "events/test/unchanged.md"),
                encoding: .utf8
            ),
            "Same\n"
        )
        expectNoDifference(
            try fixture.readFile("events/test/event.yml"),
            "name: Old\n"
        )
        #expect(FileManager.default.fileExists(atPath: workingTree.workingRepositoryURL.path))
    }

    @Test
    func livePublisherPassesPreparedPatchToProviderAndCleansUpWorkingTree() async throws {
        let fixture = try SourcePatchPublisherFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        let repositoryURL = fixture.repositoryURL
        let rootURL = fixture.rootURL
        let sourceChangeURL = try #require(URL(string: "https://source.woody.fm/events/test/pulls/1"))

        let publication = try await withDependencies {
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: rootURL
            )
        } operation: {
            try await SourcePatchPublisher.live { preparedPatch in
                expectNoDifference(
                    preparedPatch.request.location,
                    SourcePatchLocation(
                        repositoryURL: repositoryURL,
                        relativePath: "events/test"
                    )
                )
                expectNoDifference(
                    try String(
                        contentsOf: preparedPatch.workingTree.workingRepositoryURL.appending(path: "events/test/event.yml"),
                        encoding: .utf8
                    ),
                    "name: New\n"
                )
                #expect(preparedPatch.workingTree.workingRepositoryURL != repositoryURL)

                return SourcePatchPublication(sourceChangeURL: sourceChangeURL)
            }
            .publish(
                SourcePatchPublishRequest(
                    location: SourcePatchLocation(
                        repositoryURL: repositoryURL,
                        relativePath: "events/test"
                    ),
                    patch: SourcePatch(
                        fileChanges: [
                            SourcePatchFileChange(
                                path: "events/test/event.yml",
                                kind: .modified,
                                oldContents: data("name: Old\n"),
                                newContents: data("name: New\n")
                            )
                        ]
                    )
                )
            )
        }

        expectNoDifference(publication, SourcePatchPublication(sourceChangeURL: sourceChangeURL))
        expectNoDifference(try fixture.readFile("events/test/event.yml"), "name: Old\n")
        expectNoDifference(try fixture.rootContents(), ["repository"])
    }

    @Test
    func livePublisherCleansUpWorkingTreeWhenProviderFails() async throws {
        let fixture = try SourcePatchPublisherFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        let repositoryURL = fixture.repositoryURL
        let rootURL = fixture.rootURL

        let error = await #expect(throws: TestPublisherError.self) {
            try await withDependencies {
                $0.uuid = .incrementing
                $0.sourceWorkingTreeMaterializer = .live(
                    temporaryDirectoryURL: rootURL
                )
            } operation: {
                try await SourcePatchPublisher.live { _ in
                    throw TestPublisherError.failed
                }
                .publish(
                    SourcePatchPublishRequest(
                        location: SourcePatchLocation(
                            repositoryURL: repositoryURL,
                            relativePath: "events/test"
                        ),
                        patch: SourcePatch(
                            fileChanges: [
                                SourcePatchFileChange(
                                    path: "events/test/event.yml",
                                    kind: .modified,
                                    oldContents: data("name: Old\n"),
                                    newContents: data("name: New\n")
                                )
                            ]
                        )
                    )
                )
            }
        }

        expectNoDifference(error, .failed)
        expectNoDifference(try fixture.rootContents(), ["repository"])
    }

    @Test
    func dependencyDefaultsToUnconfiguredPublisher() async throws {
        let request = SourcePatchPublishRequest(
            location: SourcePatchLocation(
                repositoryURL: URL(fileURLWithPath: "/tmp/repository")
            ),
            patch: SourcePatch()
        )

        let error = await #expect(throws: SourcePatchPublisherError.self) {
            try await withDependencies {
                $0.sourcePatchPublisher = .unconfigured
            } operation: {
                @Dependency(\.sourcePatchPublisher) var publisher
                _ = try await publisher.publish(request)
            }
        }

        expectNoDifference(error, .notConfigured)
    }
}

private enum TestPublisherError: Equatable, Error {
    case failed
}

private final class SourcePatchPublisherFixture {
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SourcePatchPublisherTests-\(UUID().uuidString)")
            .standardizedFileURL
        self.repositoryURL = rootURL.appending(path: "repository").standardizedFileURL

        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func readFile(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryURL.appending(path: path),
            encoding: .utf8
        )
    }

    func rootContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: rootURL.path
        )
        .sorted()
    }

    func writeFile(_ path: String, contents: String) throws {
        let url = repositoryURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func data(_ string: String) -> Data {
    Data(string.utf8)
}
