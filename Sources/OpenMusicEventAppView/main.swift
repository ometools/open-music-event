import Foundation
import OpenMusicEventAppViewServer

switch try AppViewCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
case let .rebuildCanonicalCalendar(source, destination):
    let started = Date()
    do {
    let report = try OpenMusicEventAppViewServer.rebuildCanonicalCalendar(
        fromBackup: URL(fileURLWithPath: source),
        destination: URL(fileURLWithPath: destination)
    ) { message in
        try FileHandle.standardOutput.write(contentsOf: Data((message + "\n").utf8))
    }
    print("Elapsed: \(Date().timeIntervalSince(started)) seconds")
    guard report.passed else { exit(EXIT_FAILURE) }
    } catch {
        try FileHandle.standardError.write(contentsOf: Data("Rebuild failed: \(error)\n".utf8))
        exit(EXIT_FAILURE)
    }

case .serve:
    let configuration = try AppViewConfiguration.fromEnvironment()
    let notificationProvider = try await configuration.notificationProvider()
    let app = try OpenMusicEventAppViewServer.application(
        configuration: configuration,
        notificationProvider: notificationProvider
    )
    try await app.runService()

case .setTangledWebhookSecret(let watchID, let secretFile):
    let configuration = try AppViewConfiguration.fromEnvironment()
    guard let databaseURL = configuration.databaseURL else {
        throw AppViewCommandError.databaseUnavailable
    }
    guard let protection = configuration.webhookSecretProtection else {
        throw AppViewCommandError.protectionUnavailable
    }
    let typedWatchID = WebhookInboxDelivery.WatchID(rawValue: watchID)
    guard configuration.tangledWebhook?.watches.contains(where: { $0.id == typedWatchID }) == true
    else {
        throw AppViewCommandError.unknownWatch(watchID)
    }
    let secret: Data
    if let secretFile {
        secret = try Data(contentsOf: URL(fileURLWithPath: secretFile))
    } else {
        var input = FileHandle.standardInput.readDataToEndOfFile()
        while input.last == 0x0A || input.last == 0x0D {
            input.removeLast()
        }
        secret = input
    }
    let store = try OpenMusicEventAppViewStore(
        databaseURL: databaseURL,
        webhookSecretProtection: protection,
        initiallyReady: configuration.ingestion == nil
    )
    try await store.replaceWebhookSecret(
        secret,
        source: .tangled,
        watchID: typedWatchID
    )
    print("Stored Tangled webhook secret for \(watchID).")

case .backfillSourceArtifacts:
    let configuration = try AppViewConfiguration.fromEnvironment()
    let results = try await OpenMusicEventAppViewServer.backfillSourceArtifacts(
        configuration: configuration
    )
    for result in results {
        print(
            "Published \(result.watchID) at \(result.revision) to \(result.url) (\(result.objectKey), sha256 \(result.checksumSHA256))."
        )
    }

case .help:
    print(AppViewCommand.usage)
}

private enum AppViewCommand: Equatable {
    case rebuildCanonicalCalendar(source: String, destination: String)
    case serve
    case setTangledWebhookSecret(watchID: String, secretFile: String?)
    case backfillSourceArtifacts
    case help

    static let usage = """
        USAGE: OpenMusicEventAppView [serve]
               OpenMusicEventAppView rebuild-canonical-calendar --from-backup <path> --output <new-path>
               OpenMusicEventAppView set-tangled-webhook-secret --watch-id <watch-id> [--secret-file <path>]
               OpenMusicEventAppView backfill-source-artifacts
        """

    init(arguments: [String]) throws {
        guard let command = arguments.first else {
            self = .serve
            return
        }
        switch command {
        case "rebuild-canonical-calendar":
            guard arguments.count == 5, arguments[1] == "--from-backup", arguments[3] == "--output" else {
                throw AppViewCommandError.unexpectedArguments(Array(arguments.dropFirst()))
            }
            self = .rebuildCanonicalCalendar(source: arguments[2], destination: arguments[4])

        case "serve":
            guard arguments.count == 1 else {
                throw AppViewCommandError.unexpectedArguments(Array(arguments.dropFirst()))
            }
            self = .serve

        case "set-tangled-webhook-secret":
            var watchID: String?
            var secretFile: String?
            var index = 1
            while index < arguments.count {
                let option = arguments[index]
                guard index + 1 < arguments.count else {
                    throw AppViewCommandError.missingValue(option)
                }
                let value = arguments[index + 1]
                switch option {
                case "--watch-id":
                    watchID = value
                case "--secret-file":
                    secretFile = value
                default:
                    throw AppViewCommandError.unknownOption(option)
                }
                index += 2
            }
            guard let watchID, !watchID.isEmpty else {
                throw AppViewCommandError.watchIDMissing
            }
            self = .setTangledWebhookSecret(watchID: watchID, secretFile: secretFile)

        case "backfill-source-artifacts":
            guard arguments.count == 1 else {
                throw AppViewCommandError.unexpectedArguments(Array(arguments.dropFirst()))
            }
            self = .backfillSourceArtifacts

        case "help", "--help", "-h":
            self = .help

        default:
            throw AppViewCommandError.unknownCommand(command)
        }
    }
}

private enum AppViewCommandError: Error, CustomStringConvertible {
    case databaseUnavailable
    case missingValue(String)
    case protectionUnavailable
    case unexpectedArguments([String])
    case unknownCommand(String)
    case unknownOption(String)
    case unknownWatch(String)
    case watchIDMissing

    var description: String {
        switch self {
        case .databaseUnavailable:
            "OME_APPVIEW_DATABASE_PATH is required."
        case .missingValue(let option):
            "Option '\(option)' requires a value."
        case .protectionUnavailable:
            "OME_WEBHOOK_SECRET_KEY_PATH is required."
        case .unexpectedArguments(let arguments):
            "Unexpected arguments: \(arguments.joined(separator: " "))."
        case .unknownCommand(let command):
            "Unknown command '\(command)'.\n\(AppViewCommand.usage)"
        case .unknownOption(let option):
            "Unknown option '\(option)'."
        case .unknownWatch(let watchID):
            "The public Tangled configuration does not contain watch ID '\(watchID)'."
        case .watchIDMissing:
            "--watch-id is required."
        }
    }
}
