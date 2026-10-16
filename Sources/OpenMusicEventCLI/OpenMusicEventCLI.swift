import ATProto
import ATProtoOAuth
import ArgumentParser
import struct ArgumentParser.ValidationError
import Dependencies
import Foundation
import Noora
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSource
import TangledLexicon
import TangledXRPC

@main
struct OpenMusicEventCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ome",
        abstract: "OpenMusicEvent source repository tools.",
        subcommands: [
            ProtocolRecords.self,
            Source.self
        ]
    )
}

extension OpenMusicEventCommand {
    struct Source: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "source",
            abstract: "Work with organizer-owned OpenMusicEvent source repositories.",
            subcommands: [
                Rewrite.self,
                FestivalProImport.self,
                TangledPullIndexingRepro.self,
                TangledSourceCloneCommand.self,
                NormalizeActors.self,
                Validate.self
            ],
            defaultSubcommand: Validate.self
        )
    }
}

extension OpenMusicEventCommand.Source {
    struct Rewrite: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rewrite",
            abstract: "Read and rewrite a local source repository using the current source format."
        )

        @Argument(help: "Path to a local source repository root.")
        var source: String

        func run() async throws {
            let sourceURL = URL(filePath: source).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: sourceURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw ValidationError("Source must be an existing directory.")
            }

            let fileTree = OpenMusicEventSourceRepositoryFileTree()
            let sourceRepository = try fileTree
                .read(from: sourceURL)
                .output
                .requiredValue
            _ = try fileTree.rewrite(sourceRepository, at: sourceURL)

            print("Rewrote source repository at \(sourceURL.path)")
        }
    }
}

extension OpenMusicEventCommand.Source {
    struct TangledPullIndexingRepro: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tangled-pull-indexing-repro",
            abstract: "List Tangled pulls, close or delete one, then list again."
        )

        enum Operation: String, ExpressibleByArgument {
            case close
            case delete
        }

        @Option(help: "Target repository DID passed to sh.tangled.repo.listPulls as subject.")
        var subject: String

        @Option(help: "Pull record URI to close or delete.")
        var pullURI: String

        @Option(help: "Authenticated account DID. Defaults to the selected stored OME session, or the only stored session.")
        var account: String?

        @Option(help: "Mutation to perform after the first list.")
        var operation: Operation

        @Option(help: "Maximum pulls to request from Bobbin.")
        var limit = 50

        @Option(help: "Number of post-mutation list requests. The first request is immediate.")
        var afterPolls = 1

        @Option(help: "Seconds to wait between post-mutation list requests.")
        var pollDelay = 2.0

        func run() async throws {
            guard limit > 0 else {
                throw ValidationError("--limit must be greater than 0.")
            }
            guard afterPolls > 0 else {
                throw ValidationError("--after-polls must be greater than 0.")
            }
            guard pollDelay >= 0 else {
                throw ValidationError("--poll-delay must be greater than or equal to 0.")
            }
            guard let subjectDID = DID(subject) else {
                throw ValidationError("--subject must be a DID.")
            }
            guard let pullURI = ATProto.URI(pullURI) else {
                throw ValidationError("--pull-uri must be an AT URI.")
            }
            guard pullURI.collection == TangledNSID.pull, pullURI.rkey != nil else {
                throw ValidationError("--pull-uri must identify a sh.tangled.repo.pull record.")
            }

            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
            let session = try selectedSession(account: account)
            let accountID = session.accountID

            print("account: \(accountID.rawValue.description)")
            print("pds: \(session.pdsHost.rawValue)")
            print("subject: \(subjectDID.description)")
            print("pullURI: \(pullURI.description)")
            print("operation: \(operation.rawValue)")
            print("")

            try await withDependencies {
                $0.selectedOAuthSessionID = accountID
                OpenMusicEventOAuth.prepareDependencies(&$0)
                $0.getSelectedOAuthSessionID = { accountID }
                $0.getDefaultSession = {
                    OpenMusicEventOAuth.sessionStore.wrappedValue[accountID] ?? session
                }
                $0.getOptionalDefaultSession = {
                    OpenMusicEventOAuth.sessionStore.wrappedValue[accountID] ?? session
                }
            } operation: {
                @Dependency(XRPC.Client.self) var xrpcClient

                let before = try await listOpenPulls(
                    subject: subjectDID,
                    limit: limit,
                    xrpcClient: xrpcClient
                )
                printSnapshot("before", before, pullURI: pullURI)

                switch operation {
                case .close:
                    try await closePull(
                        pullURI,
                        accountID: accountID,
                        xrpcClient: xrpcClient
                    )
                case .delete:
                    try await deletePull(
                        pullURI,
                        xrpcClient: xrpcClient
                    )
                }

                for index in 1...afterPolls {
                    if index > 1, pollDelay > 0 {
                        try await Task.sleep(
                            nanoseconds: UInt64(pollDelay * 1_000_000_000)
                        )
                    }
                    let after = try await listOpenPulls(
                        subject: subjectDID,
                        limit: limit,
                        xrpcClient: xrpcClient
                    )
                    printSnapshot("after[\(index)]", after, pullURI: pullURI)
                }
            }
        }

        private func selectedSession(account: String?) throws -> OAuth.Session {
            let sessionStore = OpenMusicEventOAuth.sessionStore.wrappedValue

            if let account {
                guard let did = DID(account) else {
                    throw ValidationError("--account must be a DID.")
                }
                guard let session = sessionStore.sessions[did] else {
                    throw ValidationError("No stored OME OAuth session for \(did.description).")
                }
                return session
            }

            if let selectedSessionID = OpenMusicEventOAuth.selectedSessionID.wrappedValue,
               let session = sessionStore[selectedSessionID] {
                return session
            }

            if sessionStore.sessions.count == 1,
               let session = sessionStore.sessions.values.first {
                return session
            }

            let accounts = sessionStore.sessions.keys
                .map(\.description)
                .sorted()
                .joined(separator: ", ")
            throw ValidationError(
                "Pass --account to choose one stored OME OAuth session. Stored accounts: \(accounts)"
            )
        }

        private func listOpenPulls(
            subject: DID,
            limit: Int,
            xrpcClient: XRPC.Client
        ) async throws -> TangledListPullsOutput {
            try await xrpcClient.tangledListPulls(
                subject: subject,
                status: .open,
                limit: limit,
                order: .descending
            )
        }

        private func closePull(
            _ pullURI: ATProto.URI,
            accountID: Atmosphere.Account.ID,
            xrpcClient: XRPC.Client
        ) async throws {
            let record = TangledPullStatusRecord(
                pull: pullURI,
                status: .closed,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            _ = try await xrpcClient.run(
                TangledRepositoryRequests.createRecord(
                    repo: accountID.rawValue.description,
                    collection: .pullStatus,
                    record: record,
                    authorizationPolicy: .required(
                        TangledOAuthRequirements.pullStatusAuthRequirement
                    )
                )
            )
            print("mutation: created closed pull status")
            print("")
        }

        private func deletePull(
            _ pullURI: ATProto.URI,
            xrpcClient: XRPC.Client
        ) async throws {
            guard let rkey = pullURI.rkey else {
                throw ValidationError("--pull-uri must include a record key.")
            }
            _ = try await xrpcClient.run(
                TangledRepositoryRequests.deleteRecord(
                    TangledPullRecord.self,
                    repo: pullURI.authorDescription,
                    collection: .pull,
                    rkey: rkey,
                    authorizationPolicy: .required(
                        TangledOAuthRequirements.pullDeleteAuthRequirement
                    )
                )
            )
            print("mutation: deleted pull record")
            print("")
        }

        private func printSnapshot(
            _ label: String,
            _ output: TangledListPullsOutput,
            pullURI: ATProto.URI
        ) {
            let target = output.items.first { $0.uri == pullURI }

            print("\(label):")
            print("  count: \(output.items.count)")
            print("  cursor: \(output.cursor ?? "nil")")
            print("  targetPresent: \(target != nil)")

            if let target {
                print("  targetState: \(target.state.rawValue)")
                print("  targetStateUpdatedAt: \(target.stateUpdatedAt ?? "nil")")
                print("  targetTitle: \(target.value.title)")
            }

            for item in output.items.prefix(10) {
                let marker = item.uri == pullURI ? "*" : "-"
                print("  \(marker) \(item.uri.description) \(item.state.rawValue) \(item.value.title)")
            }
            print("")
        }
    }
}

private extension ATProto.URI {
    var authorDescription: String {
        switch authority {
        case let .did(did):
            did.description
        case let .handle(handle):
            handle.rawValue
        }
    }
}

extension OpenMusicEventCommand.Source {
    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Parse, validate, and insert a source repository."
        )

        @Argument(help: "Path to a local source repository root or a Tangled repository reference.")
        var source: String

        @Option(help: "Organizer DID used to scope imported event records. If omitted for a Tangled repository, the owner DID is resolved from the repository reference.")
        var organizerID: String?

        @Option(help: "Git ref to download when source is a Tangled repository reference.")
        var ref = "HEAD"

        @Option(help: "Destination directory for a downloaded Tangled source tree. If omitted, a temporary directory is used and removed.")
        var output: String?

        @Flag(name: .shortAndLong, help: "Print event-level details.")
        var verbose = false

        func run() async throws {
            let organizerID = try parsedOrganizerID()
            let outputURL = try output.map(TangledSourceCloneCommand.resolvedOutputURL)
            let result = try await OpenMusicEventSourceValidator(
                OpenMusicEventSourceValidationRequest(
                    source: source,
                    organizerID: organizerID,
                    ref: ref,
                    outputURL: outputURL
                )
            )
            .validateAndInsertIntoDefaultDatabase()

            print(result.summary.description)

            if verbose {
                print()
                for event in result.summary.events {
                    print("- \(event.eventID): \(event.name)")
                }
            }
        }

        private func parsedOrganizerID() throws -> OME.Organizer.ID? {
            guard let organizerID else { return nil }
            guard let parsedOrganizerID = OME.Organizer.ID(organizerID) else {
                throw ValidationError(OpenMusicEventSourceValidationError.invalidOrganizerID(organizerID).localizedDescription)
            }
            return parsedOrganizerID
        }
    }
}

extension OpenMusicEventCommand.Source {
    struct NormalizeActors: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "normalize-actors",
            abstract: "Resolve handle-valued contributor actors to DIDs."
        )

        @Argument(help: "Path to a local source repository root.")
        var source: String

        @Option(help: "Optional event directory under events/ to scan.")
        var event: String?

        @Flag(help: "Rewrite schedule files. Defaults to a dry run.")
        var apply = false

        @Flag(help: "Apply resolved replacements even when some handles could not be resolved.")
        var allowUnresolved = false

        @Option(
            name: .customLong("override"),
            help: "Manual handle-to-DID override in the form old.handle.example=did:plc:abc123."
        )
        var overrideArguments: [String] = []

        @Option(help: "Maximum number of handles to resolve concurrently.")
        var resolutionParallelism = 16

        @Option(help: "Per-handle resolution timeout in seconds.")
        var resolutionTimeoutSeconds = 5

        func run() async throws {
            let noora = Noora(theme: .openMusicEvent)
            guard resolutionParallelism > 0 else {
                throw ValidationError("--resolution-parallelism must be greater than zero.")
            }
            guard resolutionTimeoutSeconds > 0 else {
                throw ValidationError("--resolution-timeout-seconds must be greater than zero.")
            }

            let result = try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: URL(fileURLWithPath: source),
                    eventDirectory: event,
                    apply: apply,
                    allowUnresolved: allowUnresolved,
                    overrides: try parsedOverrides(),
                    resolutionParallelism: resolutionParallelism,
                    resolutionTimeoutSeconds: resolutionTimeoutSeconds
                )
            ) { progress in
                printProgress(progress, noora: noora)
            }

            printResult(result, noora: noora)
        }

        func parsedOverrides() throws -> [String: String] {
            var overrides: [String: String] = [:]

            for override in overrideArguments {
                let parts = override.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard parts.count == 2,
                      !parts[0].isEmpty,
                      !parts[1].isEmpty
                else {
                    throw ValidationError("Override must use handle=did form: \(override)")
                }

                let handle = String(parts[0])
                guard overrides[handle] == nil else {
                    throw ValidationError("Duplicate override for \(handle)")
                }
                overrides[handle] = String(parts[1])
            }

            return overrides
        }

        static let metricHeaders = ["Metric", "Count"]
        static let replacementHeaders = ["File", "Stage", "Performance", "Actor", "Handle", "DID", "Source"]
        static let unresolvedHandleHeaders = ["File", "Stage", "Performance", "Actor", "Handle", "Error"]

        struct OutputTables: Equatable {
            var metrics: [[String]]
            var replacements: [[String]]
            var unresolvedHandles: [[String]]
        }

        enum ProgressOutput: Equatable {
            case info(String)
            case line(String)
        }

        static func outputTables(for result: SourceActorDIDConversionResult) -> OutputTables {
            OutputTables(
                metrics: [
                    ["Replacements", "\(result.replacements.count)"],
                    ["Unresolved handles", "\(result.unresolvedHandles.count)"],
                    ["Existing DID references", "\(result.unchangedDIDReferences.count)"],
                    ["Touched files", "\(result.touchedFiles.count)"],
                ],
                replacements: result.replacements.map { replacement in
                    [
                        replacement.location.file,
                        replacement.location.stageID,
                        replacement.location.performanceTitle,
                        "\(replacement.location.actorIndex)",
                        replacement.handle,
                        replacement.did,
                        replacement.source.rawValue,
                    ]
                },
                unresolvedHandles: result.unresolvedHandles.map { unresolvedHandle in
                    [
                        unresolvedHandle.location.file,
                        unresolvedHandle.location.stageID,
                        unresolvedHandle.location.performanceTitle,
                        "\(unresolvedHandle.location.actorIndex)",
                        unresolvedHandle.handle,
                        unresolvedHandle.errorDescription,
                    ]
                }
            )
        }

        static func progressOutput(
            for progress: SourceActorDIDConversionProgress
        ) -> ProgressOutput {
            switch progress {
            case let .readingRepository(repositoryURL):
                .info("Reading source repository at \(repositoryURL.path).")

            case let .repositoryRead(eventCount):
                .line("  Read \(eventCount) event(s).")

            case let .validatingOverrides(count):
                .line("  Validating \(count) override(s).")

            case let .discoveringActors(eventDirectory):
                if let eventDirectory {
                    .info("Discovering contributor actor references in event \(eventDirectory).")
                } else {
                    .info("Discovering contributor actor references in all events.")
                }

            case let .actorsDiscovered(
                actorReferenceCount,
                handleReferenceCount,
                didReferenceCount,
                uniqueHandleCount,
                scheduleFileCount
            ):
                .line(
                    """
                      Found \(actorReferenceCount) actor reference(s) in \(scheduleFileCount) schedule file(s): \(handleReferenceCount) handle(s), \(didReferenceCount) DID(s), \(uniqueHandleCount) unique handle(s).
                    """
                )

            case let .resolvingHandles(uniqueHandleCount, overrideCount, parallelism, timeoutSeconds):
                if uniqueHandleCount == 0 {
                    .line("  No handle references need resolution.")
                } else {
                    .info("Resolving \(uniqueHandleCount) unique handle(s), including \(overrideCount) override(s), with up to \(parallelism) concurrent request(s) and \(timeoutSeconds)s timeout.")
                }

            case let .resolvingHandle(handle, index, total):
                .line("  Resolving [\(index)/\(total)] \(handle).")

            case let .handleResolved(handle, index, total, source):
                .line("    Resolved [\(index)/\(total)] \(handle) via \(source.rawValue).")

            case let .handleResolutionFailed(handle, index, total, _):
                .line("    Unresolved [\(index)/\(total)] \(handle).")

            case .buildingResult:
                .line("  Building conversion report.")

            case let .checkingApplyPreconditions(unresolvedHandleCount):
                .line("  Checking apply preconditions: \(unresolvedHandleCount) unresolved handle(s).")

            case let .applying(replacementCount, scheduleFileCount):
                .info("Applying \(replacementCount) replacement(s) across \(scheduleFileCount) schedule file(s).")

            case let .writingScheduleFile(file):
                .line("  Writing \(file).")

            case let .finished(didWrite):
                if didWrite {
                    .line("  Source write finished.")
                } else {
                    .line("  Dry-run scan finished.")
                }
            }
        }

        private func printProgress(
            _ progress: SourceActorDIDConversionProgress,
            noora: Noora
        ) {
            switch Self.progressOutput(for: progress) {
            case let .info(message):
                noora.info(.alert(TerminalText(stringLiteral: message)))

            case let .line(message):
                noora.passthrough(TerminalText(stringLiteral: "\(message)\n"))
            }
        }

        private func printResult(
            _ result: SourceActorDIDConversionResult,
            noora: Noora = Noora(theme: .openMusicEvent)
        ) {
            let outputTables = Self.outputTables(for: result)

            if result.didWrite {
                noora.success("Source actor DID conversion applied.")
            } else {
                noora.info("Source actor DID conversion dry run.")
            }

            noora.table(headers: Self.metricHeaders, rows: outputTables.metrics)

            if !outputTables.replacements.isEmpty {
                noora.table(headers: Self.replacementHeaders, rows: outputTables.replacements)
            }

            if !outputTables.unresolvedHandles.isEmpty {
                noora.warning("Some contributor actor handles could not be resolved.")
                noora.table(headers: Self.unresolvedHandleHeaders, rows: outputTables.unresolvedHandles)
            }
        }
    }
}

private extension Theme {
    static let openMusicEvent = Theme(
        primary: "336699",
        secondary: "C85A9C",
        muted: "6B7280",
        accent: "F5C542",
        danger: "D64545",
        success: "4F9D69",
        info: "2D8CBA",
        selectedRowText: "FFFFFF",
        selectedRowBackground: "336699"
    )
}
