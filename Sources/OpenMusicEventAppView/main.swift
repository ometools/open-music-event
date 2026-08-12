import Foundation
import OpenMusicEventAppViewServer

switch try AppViewCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
case .serve:
    let configuration = try AppViewConfiguration.fromEnvironment()
    let app = try OpenMusicEventAppViewServer.application(configuration: configuration)
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
        notificationDestinationProtection: configuration.notificationDestinationProtection,
        webhookSecretProtection: protection,
        initiallyReady: configuration.ingestion == nil
    )
    try await store.replaceWebhookSecret(
        secret,
        source: .tangled,
        watchID: typedWatchID
    )
    print("Stored Tangled webhook secret for \(watchID).")

case .help:
    print(AppViewCommand.usage)
}

private enum AppViewCommand: Equatable {
    case serve
    case setTangledWebhookSecret(watchID: String, secretFile: String?)
    case help

    static let usage = """
        USAGE: OpenMusicEventAppView [serve]
               OpenMusicEventAppView set-tangled-webhook-secret --watch-id <watch-id> [--secret-file <path>]
        """

    init(arguments: [String]) throws {
        guard let command = arguments.first else {
            self = .serve
            return
        }
        switch command {
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
