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
            let preferences = try Artist.Preferences.fetchOne(db, key: self.artistID)
            return (artist, performances, preferences)
        }

        await withErrorReporting {
            for try await (artist, performances, preferences) in combinedQuery.values() {
                logger.info("Selected Artist: \(artist.name) with: \(performances)")
                self.artist = artist
                self.performances = performances
                self.isFavorite = preferences?.isFavorite ?? false
            }
        }
    }
    
    func toggleFavorite() async {
        @Dependency(\.defaultDatabase) var database
        
        await withErrorReporting {
            try await database.write { db in
                try Artist.Preferences.toggleFavorite(for: self.artistID, in: db)
            }
        }
    }

    let artistID: Artist.ID
    var artist: Artist = .placeholder
    var performances: [PerformanceDetailRow.ArtistPerformance] = []
    var isFavorite: Bool = false
}


struct ArtistDetailView: View {
    var store: ArtistDetail

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
                            ArtistLinkView(link: link)
                        }
                    }
                }
            }
        )
        .listStyle(.plain)
        .task(id: store.artist.id) { await self.store.task() }
        .id(store.artist.id)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.toggleFavorite() }
                } label: {
                    Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(store.isFavorite ? .red : .primary)
                }
            }
        }

    }

}


struct ArtistLinkView: View {
    var link: Artist.Link
    @Environment(\.openURL) var openURL

    var body: some View {
        Button {
            var urlToOpen = link.url
            if urlToOpen.scheme == nil {
                urlToOpen = URL(string: "https://\(urlToOpen.absoluteString)")!
            }
            self.openURL(urlToOpen)
        } label: {
            HStack(spacing: 12) {
                link.icon
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)

                Text(link.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                Icons.externalLink
                    .font(.caption)
                    .foregroundStyle(.secondary)
//                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
//        .contentShape(Rectangle())
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
        #if os(Android)
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
