import ArgumentParser
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

extension OpenMusicEventCommand.Source {
    struct FestivalProImport: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "festivalpro-import",
            abstract: "Import FestivalPro contributor profiles into an OpenMusicEvent source repository."
        )

        @Argument(help: "Path to the FestivalPro JSON export.")
        var export: String

        @Argument(help: "Path to the OpenMusicEvent source repository root.")
        var source: String

        @Option(help: "Event directory under events/ to receive the contributor profiles.")
        var event: String

        @Flag(help: "Print the import summary without rewriting the source repository.")
        var dryRun = false

        func run() async throws {
            let exportURL = URL(filePath: export).standardizedFileURL
            let sourceURL = URL(filePath: source).standardizedFileURL
            let eventURL = sourceURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: event, directoryHint: .isDirectory)

            guard FileManager.default.fileExists(atPath: exportURL.path) else {
                throw ValidationError("FestivalPro export does not exist: \(exportURL.path)")
            }
            guard FileManager.default.fileExists(atPath: eventURL.path) else {
                throw ValidationError("Source event directory does not exist: \(eventURL.path)")
            }

            let importer = FestivalProContributorImporter()
            let export = try FestivalProExport(data: Data(contentsOf: exportURL))
            let contributors = try importer.contributors(from: export)
            let summary = importer.summary(for: export, contributors: contributors)

            print(summary.description)
            guard !dryRun else { return }

            let fileTree = OpenMusicEventSourceRepositoryFileTree()
            var repository = try fileTree.read(from: sourceURL).output.requiredValue
            guard let eventIndex = repository.events.firstIndex(where: { $0.directoryName == event }) else {
                throw ValidationError("Source repository does not contain events/\(event).")
            }

            repository.events[eventIndex].components.contributors = contributors
            _ = try fileTree.rewrite(repository, at: sourceURL)
        }
    }
}

struct FestivalProContributorImporter {
    func contributors(
        from export: FestivalProExport
    ) throws -> [FileContent<ContributorDTO>] {
        try export.contacts
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .reduce(into: [String: [FestivalProArtist]]()) { profiles, contact in
                guard let name = contact.value.companyName.nonEmpty else { return }
                profiles[name, default: []].append(contact.value)
            }
            .map { name, profiles in
                try FileContent(
                    fileName: sourceFileName(for: name, profiles: profiles),
                    fileType: "md",
                    data: contributor(name: name, profiles: profiles)
                )
            }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    func summary(
        for export: FestivalProExport,
        contributors: [FileContent<ContributorDTO>]
    ) -> FestivalProImportSummary {
        FestivalProImportSummary(
            contactCount: export.contacts.count,
            contributorCount: contributors.count,
            contributorNamesWithoutProfiles: export.contacts.values.filter { $0.companyName.nonEmpty == nil }.count
        )
    }

    private func contributor(name: String, profiles: [FestivalProArtist]) -> ContributorDTO {
        let profiles = profiles.sorted(by: FestivalProArtist.contactOrder)
        return ContributorDTO(
            name: name,
            bio: firstNonEmpty(\\.artistBio, in: profiles),
            images: [
                firstURL(\\.artistPressPhotoID, in: profiles).map {
                    SourceImageAsset(
                        source: .url($0),
                        role: .photo,
                        renderKind: .fullImage,
                        materializationPolicy: .lazy
                    )
                },
                firstURL(\\.artistLogoID, in: profiles).map {
                    SourceImageAsset(
                        source: .url($0),
                        role: .logo,
                        renderKind: .transparent,
                        materializationPolicy: .lazy
                    )
                },
            ].compactMap { $0 },
            links: links(in: profiles)
        )
    }

    private func firstNonEmpty(
        _ keyPath: KeyPath<FestivalProArtist, String?>,
        in profiles: [FestivalProArtist]
    ) -> String? {
        profiles.lazy.map(keyPath).compactMap(\\.nonEmpty).first
    }

    private func firstURL(
        _ keyPath: KeyPath<FestivalProArtist, String?>,
        in profiles: [FestivalProArtist]
    ) -> URL? {
        firstNonEmpty(keyPath, in: profiles).flatMap(URL.init(string:))
    }

    private func links(in profiles: [FestivalProArtist]) -> [ExternalPlatform.Link]? {
        let links = profiles
            .flatMap { profile in
                [
                    (profile.soundcloud, ExternalPlatform.soundcloud),
                    (profile.youtube, .youtube),
                    (profile.facebook, .facebook),
                    (profile.instagram, .instagram),
                    (profile.spotify, .spotify),
                    (profile.website, .website),
                ]
            }
            .compactMap { value, platform in
                value.nonEmpty.flatMap(URL.init(string:)).map { ExternalPlatform.Link(url: $0, platform: platform) }
            }

        let uniqueLinks = Dictionary(grouping: links, by: { "\($0.platform?.rawValue ?? "")|\($0.url.absoluteString)" })
            .compactMap(\\.value.first)
            .sorted { lhs, rhs in
                lhs.url.absoluteString == rhs.url.absoluteString
                    ? (lhs.platform?.rawValue ?? "") < (rhs.platform?.rawValue ?? "")
                    : lhs.url.absoluteString < rhs.url.absoluteString
            }
        return uniqueLinks.isEmpty ? nil : uniqueLinks
    }

    private func sourceFileName(for name: String, profiles: [FestivalProArtist]) -> String {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safeName.isEmpty ? "festivalpro-\(profiles.sorted(by: FestivalProArtist.contactOrder).first?.contactID ?? "unknown")" : safeName
    }
}

struct FestivalProImportSummary: Equatable {
    var contactCount: Int
    var contributorCount: Int
    var contributorNamesWithoutProfiles: Int

    var description: String {
        """
        FestivalPro import ready.
        Contacts: \(contactCount)
        Contributors: \(contributorCount)
        Contacts without a contributor name: \(contributorNamesWithoutProfiles)
        """
    }
}

struct FestivalProExport: Decodable {
    var contacts: [String: FestivalProArtist]

    init(data: Data) throws {
        contacts = try JSONDecoder().decode([String: FestivalProArtist].self, from: data)
    }
}

struct FestivalProArtist: Decodable {
    var contactID: String?
    var companyName: String?
    var artistBio: String?
    var artistPressPhotoID: String?
    var artistLogoID: String?
    var soundcloud: String?
    var youtube: String?
    var facebook: String?
    var instagram: String?
    var spotify: String?
    var website: String?

    enum CodingKeys: String, CodingKey {
        case contactID = "Contact ID"
        case companyName = "Company Name"
        case artistBio = "Artist Bio"
        case artistPressPhotoID = "Artist Press Photo ID"
        case artistLogoID = "Artist Logo ID"
        case soundcloud = "Soundcloud:"
        case youtube = "Youtube:"
        case facebook = "Facebook"
        case instagram = "Instagram"
        case spotify = "Spotify"
        case website = "Website"
    }

    static func contactOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        switch (Int(lhs.contactID ?? ""), Int(rhs.contactID ?? "")) {
        case let (lhs?, rhs?): lhs < rhs
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): (lhs.contactID ?? "") < (rhs.contactID ?? "")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
