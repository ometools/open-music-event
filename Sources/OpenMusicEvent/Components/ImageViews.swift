//
//  EntityImageViews.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/19/25.
//

//
//  OrganizerDetails.swift
//  event-viewer
//
//  Created by Woodrow Melling on 3/25/25.
//

import Foundation
import Observation
import  SwiftUI; import SkipFuse
import Dependencies
// import SharingGRDB
import CoreModels

struct OrganizerIconView: View {
    let organizer: Organizer

    var body: some View {
        CachedAsyncImage(url: organizer.iconImageURL, renderingMode: .template)
    }
}

struct OrganizerImageView: View {
    let organizer: Organizer

    var body: some View {
        CachedAsyncImage(url: organizer.imageURL)
    }
}

struct EventIconImageView: View {
    var event: MusicEvent

    var body: some View {
        CachedAsyncImage(url: event.iconImageURL, renderingMode: .template)
    }
}

struct ArtistImageView<P>: View {
    var placeholder: P

    init(
        artist: Artist,
        @ViewBuilder placeholder: () -> P
    ) {
        self.imageURL = artist.imageURL
        self.placeholder = placeholder()
    }


    init(
        imageURL: URL?,
        @ViewBuilder placeholder: () -> P
    ) {
        self.imageURL = imageURL
        self.placeholder = placeholder()
    }

    var imageURL: URL?

    var body: some View {
        CachedAsyncImage(url: imageURL)
    }
}

struct ArtistIconView: View {
    var artist: Artist

    init(artist: Artist) {
        self.artist = artist
    }

    var body: some View {
        CachedAsyncImage(url: artist.imageURL)
    }
}

import  SwiftUI; import SkipFuse
// import SharingGRDB


//#Preview() {
//    try! prepareDependencies {
//        $0.musicEventID = 0
//        $0.defaultDatabase = try appDatabase()
//    }
//    retStage.Legend()
//}


extension Stage {
    static var placeholder: Stage {
        Stage.init(
            id: "",
            musicEventID: nil,
            sortIndex: 0,
            name: "",
            iconImageURL: nil,
            color: .init(0)
        )
    }
}

import GRDB

struct StageImageView: View {
    let stageID: Stage.ID

    var body: some View {
        StageLoader(stageID: stageID) { stage in
            CachedAsyncImage(url: stage.iconImageURL)
        }
    }
}
struct StageIconView: View {
    public init(stageID: Stage.ID) {
        self.stageID = stageID
    }

    let stageID: Stage.ID

    @Environment(\.colorScheme) var colorScheme
    @Dependency(\.defaultDatabase) var database

    public var body: some View {
        StageLoader(stageID: stageID) { stage in
            CachedAsyncImage(
                url: stage.iconImageURL,
                contentMode: .fit,
                renderingMode: .template
            )
        }
    }

    struct Placeholder: View {
        var stageName: String

        var symbol: String {
            stageName
                .split(separator: " ")
                .filter { !$0.contains("The") }
                .compactMap { $0.first.map(String.init) }
                .joined()
        }

        var body: some View {
            ZStack {
                Text(symbol)
                    .font(.system(size: 300, weight: .heavy))
                    #if os(iOS)
                    .minimumScaleFactor(0.001)
                    #endif
                    .padding()
            }
        }
    }
}

public struct StageLoader<Content: View>: View {

    var stageID: Stage.ID
    @State var stage: Stage?
    var content: (Stage) -> Content

    init(stageID: Stage.ID, content: @escaping (Stage) -> Content) {
        self.stageID = stageID
        self.content = content
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some View {
        Group {
            if let stage {
                content(stage)
            } else {
                ProgressView()
            }
        }
        .task(id: stageID) {
            let query = ValueObservation.tracking { db in
                try Stage.fetchOne(db, id: stageID)
            }

            await withErrorReporting {
                for try await stage in query.values(in: database) {
                    if let stage {
                        self.stage = stage
                    }
                }
            }
        }
    }
}


public extension Stage {
    struct Legend: View {
        // TODO: Replace @FetchAll with GRDB query
        var stages: [Stage.ID] = []

        public var body: some View {
            HStack {
                ForEach(stages, id: \.self) {
                    StageIconView(stageID: $0)
                        .frame(square: 50)
                }
            }
        }
    }

}

