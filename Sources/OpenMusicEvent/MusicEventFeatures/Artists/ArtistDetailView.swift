//
//  ArtistDetailView.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels
import Dependencies

extension Artist {
    static let placeholder = Artist(
        id: .init(""),
        musicEventID: nil,
        name: "",
        bio: "",
        imageURL: nil,
        logoURL: nil,
        kind: nil,
        links: []
    )
}


@MainActor
@Observable
class ArtistDetail {
    init(artistID: Artist.ID) {
        self.artistID = artistID
    }

    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "ArtistDetailPage")

    func task() async {

        let combinedQuery = ValueObservation.tracking { db in
            let artist = try Artist.find(db, id: self.artistID)
            let performances = try Queries.fetchPerformances(for: self.artistID, from: db)
            return (artist, performances)
        }

        await withErrorReporting {
            for try await (artist, performances) in combinedQuery.values() {
                logger.info("Selected Artist: \(artist.name)")
                self.artist = artist
                self.performances = performances
            }
        }
    }

    let artistID: Artist.ID
    var artist: Artist = .placeholder
    var performances: [PerformanceDetailRow.ArtistPerformance] = []
}


struct ArtistDetailView: View {
    @State var store: ArtistDetail

    var meshColors: [Color] {
        store.performances.map(\.stageColor.swiftUIColor)
    }

    var body: some View {
        
        StretchyHeaderList(
            title: Text(store.artist.name),
            stretchyContent: {
                CachedAsyncImage(url: store.artist.imageURL)
//                ArtistImageView(artist: store.artist) {
//                    if let stage = store.performances.compactMap(\.stageID).first {
//                        StageImageView(stageID: stage)
//                    }
//                }
            },
            listContent: {
                ForEach(store.performances) { performance in
                    PerformanceDetailRow(performance: performance)
                }

                if let bioString = store.artist.bio {
                    MarkdownText(bioString)
                }

                // MARK: Socials
                if !store.artist.links.isEmpty {
                    Section("Links") {
                        ForEach(store.artist.links, id: \.url) { link in
                            Link(link.url.absoluteString, destination: link.url)
                                #if os(iOS)
                                .foregroundStyle(.tint)
                                #endif
                        }
                    }
                    
                }
            }
        )
        .listStyle(.plain)
        .task { await self.store.task() }
        .id(store.artist.id)

    }

}
//
//#Preview {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//    return ArtistDetailView(store: .init(artistID: 0))
//}

public extension OMEColor {
    var swiftUIColor: SwiftUI.Color {
        return Color(
            red: Double((self.rawValue >> 16) & 0xFF) / 255.0,
            green: Double((self.rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(self.rawValue & 0xFF) / 255.0
        )
    }
}

public extension Artist.Kind {
    var symbol: some View {
        switch self.type {
        case "dj": Image(systemName: "person")
        default:
            Image(systemName: "person")
        }
    }
}


struct MarkdownText: View {
    init(_ text: String) {
        self.text = text
    }
    var text: String

    var body: some View {
        #if SKIP
        // Skip seems to render markdown rather nicely without having to go through AttributedString, 
        Text(text)
        #else
        if let bioMarkdown = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(bioMarkdown)
        } else {
            Text(text)
        }
        #endif
    }
}
