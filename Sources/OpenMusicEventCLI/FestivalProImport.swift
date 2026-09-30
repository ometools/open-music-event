import ArgumentParser
import struct ArgumentParser.ValidationError
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
        var profilesByName: [String: [FestivalProArtist]] = [:]
        for contact in export.contacts.sorted(by: { $0.key < $1.key }) {
            guard let name = contact.value.companyName,
                  !name.isEmpty
            else { continue }
            profilesByName[name, default: []].append(contact.value)
        }

        var contributors: [FileContent<ContributorDTO>] = []
        for (name, profiles) in profilesByName {
            contributors.append(
                try FileContent(
                    fileName: sourceFileName(for: name, profiles: profiles),
                    fileType: "md",
                    data: contributor(name: name, profiles: profiles)
                )
            )
        }
        return contributors.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    func summary(
        for export: FestivalProExport,
        contributors: [FileContent<ContributorDTO>]
    ) -> FestivalProImportSummary {
        FestivalProImportSummary(
            contactCount: export.contacts.count,
            contributorCount: contributors.count,
            contributorNamesWithoutProfiles: export.contacts.values.filter { artist in
                guard let name = artist.companyName else { return true }
                return name.isEmpty
            }
            .count
        )
    }

    private func contributor(name: String, profiles: [FestivalProArtist]) -> ContributorDTO {
        let profiles = profiles.sorted(by: FestivalProArtist.contactOrder)
        let photo = firstURL(\.artistPressPhotoID, in: profiles).map {
            SourceImageAsset(
                source: .url($0),
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        }
        let logo = firstURL(\.artistLogoID, in: profiles).map {
            SourceImageAsset(
                source: .url($0),
                role: .logo,
                renderKind: .transparent,
                materializationPolicy: .lazy
            )
        }
        return ContributorDTO(
            name: name,
            bio: firstNonEmpty(\.artistBio, in: profiles),
            images: [photo, logo].compactMap { $0 },
            links: links(in: profiles)
        )
    }

    private func firstNonEmpty(
        _ keyPath: KeyPath<FestivalProArtist, String?>,
        in profiles: [FestivalProArtist]
    ) -> String? {
        for profile in profiles {
            guard let value = profile[keyPath: keyPath],
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }

    private func firstURL(
        _ keyPath: KeyPath<FestivalProArtist, String?>,
        in profiles: [FestivalProArtist]
    ) -> URL? {
        firstNonEmpty(keyPath, in: profiles).flatMap(URL.init(string:))
    }

    private func links(in profiles: [FestivalProArtist]) -> [ExternalPlatform.Link]? {
        var links: [ExternalPlatform.Link] = []
        for profile in profiles {
            appendLink(profile.soundcloud, platform: .soundcloud, to: &links)
            appendLink(profile.youtube, platform: .youtube, to: &links)
            appendLink(profile.facebook, platform: .facebook, to: &links)
            appendLink(profile.instagram, platform: .instagram, to: &links)
            appendLink(profile.spotify, platform: .spotify, to: &links)
            appendLink(profile.website, platform: .website, to: &links)
        }

        var uniqueLinksByKey: [String: ExternalPlatform.Link] = [:]
        for link in links {
            let key = "\(link.platform?.rawValue ?? "")|\(link.url.absoluteString)"
            if uniqueLinksByKey[key] == nil {
                uniqueLinksByKey[key] = link
            }
        }
        let uniqueLinks = uniqueLinksByKey.values.sorted { lhs, rhs in
            lhs.url.absoluteString == rhs.url.absoluteString
                ? (lhs.platform?.rawValue ?? "") < (rhs.platform?.rawValue ?? "")
                : lhs.url.absoluteString < rhs.url.absoluteString
        }
        return uniqueLinks.isEmpty ? nil : uniqueLinks
    }

    private func appendLink(
        _ value: String?,
        platform: ExternalPlatform,
        to links: inout [ExternalPlatform.Link]
    ) {
        guard let value,
              !value.isEmpty,
              let url = URL(string: value)
        else { return }
        links.append(ExternalPlatform.Link(url: url, platform: platform))
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
