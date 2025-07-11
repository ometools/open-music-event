//
//  FestivalProImport.swift
//  open-music-event
//
//  Created by Claude Code on 7/12/25.
//

import ArgumentParser
import CoreModels
import OpenMusicEventParser
import Dependencies
import Foundation
import OSLog
import CustomDump

struct FestivalProImport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "festivalpro-import",
        abstract: "Import artist profiles from FestivalPro JSON export"
    )

    @Argument(help: "The path to the FestivalPro JSON file")
    var jsonPath: String

    @Argument(help: "The path to the OpenFestival event directory")
    var eventPath: String

    @Flag(name: .shortAndLong, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Perform a dry run, without actually modifying the files")
    var dryRun: Bool = false

    func run() async throws {
        Logger.cli.info("Importing artists from FestivalPro JSON: \(jsonPath)")
        Logger.cli.info("Target event directory: \(eventPath)")

        guard FileManager.default.fileExists(atPath: jsonPath) else {
            Logger.cli.error("❌ JSON file not found at path: \(jsonPath)")
            throw ExitCode.failure
        }

        guard FileManager.default.fileExists(atPath: eventPath) else {
            Logger.cli.error("❌ Event directory not found at path: \(eventPath)")
            throw ExitCode.failure
        }

        do {
            try await importArtistsFromFestivalPro(jsonPath: jsonPath, eventPath: eventPath)
            Logger.cli.info("✅ Artists imported successfully! 🎉")
        } catch {
            Logger.cli.error("❌ Failed to import artists: \(error.localizedDescription)")
            throw error
        }
    }

    private func importArtistsFromFestivalPro(jsonPath: String, eventPath: String) async throws {
        let jsonData = try Data(contentsOf: URL(filePath: jsonPath))
        let festivalProArtists = try JSONDecoder().decode(FestivalProExport.self, from: jsonData)

        print("Found \(festivalProArtists.values.count) artists in FestivalPro export")

        // Parse all artists first
        let artists = try festivalProArtists.map { contact, artist in
            if verbose {
                print("Parsing: \(contact)")
            }
            let name = try artist.companyName.nilIfEmpty.required

            let parsedArtist = CoreModels.Artist.Draft(
                id: nil,
                musicEventID: nil,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: artist.artistBio.nilIfEmpty,
                imageURL: artist.artistPressPhotoID.flatMap { URL(string: $0) },
                logoURL: artist.artistLogoID.flatMap { URL(string: $0) },
                kind: artist.typeOfAct.nilIfEmpty.flatMap { .init(stringLiteral: $0) },
                links: [
                    .init(artist.soundcloud, .soundcloud),
                    .init(artist.youtube, .youtube),
                    .init(artist.facebook, .facebook),
                    .init(artist.instagram, .instagram),
                    .init(artist.spotify, .spotify),
                    .init(artist.website, .website),
                ].compactMap { $0 }
            )

            if verbose {
                customDump(parsedArtist, name: name)
            }

            return parsedArtist
        }

        // Show parsing statistics
        try showArtistStatistics(artists)

        // Ask for user confirmation before writing to disk
        print("\n📝 Ready to write \(artists.count) artists to disk.")
        print("Continue? (y/N): ", terminator: "")
        
        let response = readLine()?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == "y" || response == "yes" else {
            print("❌ Import cancelled by user.")
            return
        }

        // Write artists to filesystem
        try await writeArtistsToDisk(artists: artists, eventPath: eventPath)
        
        print("✅ Successfully wrote \(artists.count) artists to disk! 🎉")
    }

    private func showArtistStatistics(_ artists: [CoreModels.Artist.Draft]) throws {
        let totalCount = artists.count
        let withBios = artists.filter { $0.bio != nil }.count
        let withImages = artists.filter { $0.imageURL != nil }.count
        let withLogos = artists.filter { $0.logoURL != nil }.count
        let withLinks = artists.filter { !$0.links.isEmpty }.count
        
        // Count by artist kind
        let kindCounts = Dictionary(grouping: artists.compactMap { $0.kind?.type }) { $0 }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        print("\n📊 Artist Statistics:")
        print("  Total artists: \(totalCount)")
        print("  With bios: \(withBios) (\(Int(Double(withBios)/Double(totalCount)*100))%)")
        print("  With images: \(withImages) (\(Int(Double(withImages)/Double(totalCount)*100))%)")
        print("  With logos: \(withLogos) (\(Int(Double(withLogos)/Double(totalCount)*100))%)")
        print("  With social links: \(withLinks) (\(Int(Double(withLinks)/Double(totalCount)*100))%)")
        
        if !kindCounts.isEmpty {
            print("\n🎭 Artist Types:")
            for (kind, count) in kindCounts {
                print("  \(kind): \(count)")
            }
        }
    }

    private func writeArtistsToDisk(artists: [CoreModels.Artist.Draft], eventPath: String) async throws {

        let artistsDir = URL(filePath: eventPath).appendingPathComponent("artists")

        // Create artists directory if it doesn't exist
        try FileManager.default.createDirectory(at: artistsDir, withIntermediateDirectories: true)

        let conversion = ArtistConversion()

        let files: [FileContent<Data>] = try artists.map { try conversion.unapply($0) }

        for file in files {
            print("✅ Writing \(file.fileName)")
            if !dryRun {
                try File.Many(withExtension: .markdown).write(files, to: artistsDir)
            }
            print("✅ Wrote \(file.fileName)")
        }
    }
}


import FileTree
// FileTree public things



extension CoreModels.Artist.Link {
    public init?(_ urlString: String?, _ type: Self.LinkType) {
        // TODO: Parse/Warn
        guard let urlString, let url = URL(string: urlString) else { return nil }

        self.init(url: url, type: type)
    }
}

extension Optional {
    var required: Wrapped {
        get throws {
            if let self {
                return self
            } else {
                throw NotFound()
            }
        }
    }
}

extension Optional where Wrapped == String {
    var nilIfEmpty: Self {
        self.flatMap { $0.nilIfEmpty }
    }
}

struct NotFound: Error {}
// MARK: - FestivalPro Data Models
typealias FestivalProExport = [String : FestivalProArtist]

import Foundation

// MARK: - FestivalProArtist
// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let festivalProArtist = try? JSONDecoder().decode(FestivalProArtist.self, from: jsonData)

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let festivalProArtist = try? JSONDecoder().decode(FestivalProArtist.self, from: jsonData)

import Foundation

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let festivalProArtist = try? JSONDecoder().decode(FestivalProArtist.self, from: jsonData)

import Foundation

// MARK: - FestivalProArtist
struct FestivalProArtist: Codable {
    let contactID: String?
    let contactFirstName: String?
    let contactLastName: String?
    let contactEmail: String?
    let cellMobile: String?
    let companyName: String?
    let id: String?
    let address2: String?
    let address3: String?
    let address4: String?
    let zipPostcode: String?
    let country: String?
    let phone: String?
    let marketing: String?
    let assignedTo: String?
    let notes: String?
    let type: String?
    let accommodationNotes: [String]?
    let bookingName: [String]?
    let isProduction: String?
    let numberOfGuestPasses: String?
    let accommodation: String?
    let accommodationBuyoutAmount: String?
    let camping: String?
    let numberOfVehiclePasses: String?
    let artistConfirmed: String?
    let typeOfAct: String?
    let stage: [String]?
    let stage2: [String]?
    let stage3: [String]?
    let performanceName: [String]?
    let performanceDate: [String]?
    let performanceDate2: [String]?
    let performanceFee: String?
    let performanceFeeCurrency: String?
    let paymentTerms: String?
    let billing: String?
    let riderType: String?

    //    let numberOfArtistPasses: String? // Removed due to being both string and array values
    let bookingDetails: String?
    let typeOfAct2: String?
    let loadInTime: String?
    let entryGateArtistSGuests: String?
    let parkingArtistSGuests: String?
    let entryGate: String?
    let artistBio: String?
    let artistPressPhoto: String?
    let artistPressPhotoID: String?
    let artistLogo: String?
    let artistLogoID: String?
    let electronicPressKit: String?
//    let technicalRiderText: String?
//    let technicalRiderStagePlotUpload: String?
//    let technicalRiderStagePlotUploadID: String?
    let hospitalityRider: String?
    let consentToDancePerformances: String?
    let onSiteTransportation: String?
    let onSiteTransportationNeeds: String?
//    let performanceArtCostumes: String?
//    let performanceArtCostumesID: String?
    let artistPressPhoto2: String?
    let financialInstitution: String?
    let institutionNumber3Digit: String?
    let transitNumber5Digit: String?
    let accountNumber: String?
    let minimumSetsPerformers: String?
    let numberOfGroupMembersPerformers: String?
    let soundcloud: String?
    let youtube: String?
    let facebook: String?
    let instagram: String?
    let spotify: String?
    let website: String?
//    let artistMealVoucher: String?
//    let mealTicketLiveScan: String?
    let crewMealPreference: String?
    let arrivalFlightFrom: ArrivalFlightFrom?
    let groundTransport: GroundTransport?

    enum CodingKeys: String, CodingKey {
        case contactID = "Contact ID"
        case contactFirstName = "Contact First Name"
        case contactLastName = "Contact Last Name"
        case contactEmail = "Contact Email"
        case cellMobile = "Cell/Mobile"
        case companyName = "Company Name"
        case id = "ID"
        case address2 = "Address2"
        case address3 = "Address3"
        case address4 = "Address4"
        case zipPostcode = "Zip/Postcode"
        case country = "Country"
        case phone = "Phone"
        case marketing = "Marketing"
        case assignedTo = "Assigned To"
        case notes = "Notes"
        case type = "Type"
        case accommodationNotes = "Accommodation Notes"
        case bookingName = "Booking Name"
        case isProduction = "Is Production"
        case numberOfGuestPasses = "Number of Guest passes"
        case accommodation = "Accommodation"
        case accommodationBuyoutAmount = "Accommodation Buyout Amount"
        case camping = "Camping:"
        case numberOfVehiclePasses = "Number of vehicle passes"
        case artistConfirmed = "Artist Confirmed"
        case typeOfAct = "Type of Act"
        case stage = "Stage"
        case stage2 = "Stage (2)"
        case stage3 = "Stage (3)"
        case performanceName = "Performance Name"
        case performanceDate = "Performance Date"
        case performanceDate2 = "Performance Date (2)"
        case performanceFee = "Performance Fee"
        case performanceFeeCurrency = "Performance Fee Currency"
        case paymentTerms = "Payment Terms"
        case billing = "Billing"
        case riderType = "Rider Type"
//        case numberOfArtistPasses = "Number of Artist Passes"
        case bookingDetails = "Booking details"
        case typeOfAct2 = "Type of Act 2"
        case loadInTime = "Load in Time"
        case entryGateArtistSGuests = "Entry Gate (Artist's Guests)"
        case parkingArtistSGuests = "Parking (Artist's Guests)"
        case entryGate = "Entry Gate"
        case artistBio = "Artist Bio"
        case artistPressPhoto = "Artist Press Photo"
        case artistPressPhotoID = "Artist Press Photo ID"
        case artistLogo = "Artist Logo"
        case artistLogoID = "Artist Logo ID"
        case electronicPressKit = "Electronic Press Kit"
//        case technicalRiderText = "Technical Rider Text"
//        case technicalRiderStagePlotUpload = "Technical Rider / Stage Plot Upload"
//        case technicalRiderStagePlotUploadID = "Technical Rider / Stage Plot Upload ID"
        case hospitalityRider = "Hospitality Rider"
        case consentToDancePerformances = "Consent to Dance Performances"
        case onSiteTransportation = "On-Site Transportation"
        case onSiteTransportationNeeds = "On-Site Transportation Needs"
//        case performanceArtCostumes = "Performance Art Costumes"
//        case performanceArtCostumesID = "Performance Art Costumes ID"
        case artistPressPhoto2 = "Artist Press Photo (2)"
        case financialInstitution = "Financial Institution"
        case institutionNumber3Digit = "Institution Number (3 Digit)"
        case transitNumber5Digit = "Transit Number (5 Digit)"
        case accountNumber = "Account Number"
        case minimumSetsPerformers = "Minimum Sets (Performers)"
        case numberOfGroupMembersPerformers = "Number of Group Members (Performers)"
        case soundcloud = "Soundcloud:"
        case youtube = "Youtube:"
        case facebook = "Facebook"
        case instagram = "Instagram"
        case spotify = "Spotify"
        case website = "Website"
//        case artistMealVoucher = "Artist Meal Voucher "
//        case mealTicketLiveScan = "Meal Ticket Live Scan"
        case crewMealPreference = "Crew Meal Preference"
        case arrivalFlightFrom = "Arrival Flight From"
        case groundTransport = "Ground Transport"
    }
}

// MARK: - ArrivalFlightFrom
struct ArrivalFlightFrom: Codable {
    let arrivalFlightFrom: [String]?
    let arrivalFlightNumber: [String]?
    let arrivalFlightTime: [String]?
    let arrivalNumberOfPeopleFlying: [String]?

    enum CodingKeys: String, CodingKey {
        case arrivalFlightFrom = "Arrival Flight From"
        case arrivalFlightNumber = "Arrival Flight Number"
        case arrivalFlightTime = "Arrival  Flight Time"
        case arrivalNumberOfPeopleFlying = "Arrival  Number of People Flying"
    }
}

// MARK: - GroundTransport
struct GroundTransport: Codable {
    let groundTransport: [String]?
    let vehicleType: [String]?
    let pickUpTimeDuration: [String]?

    enum CodingKeys: String, CodingKey {
        case groundTransport = "Ground Transport"
        case vehicleType = "Vehicle Type"
        case pickUpTimeDuration = "Pick Up Time/Duration"
    }
}
