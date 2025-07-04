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
        AsyncImage(url: organizer.iconImageURL) { image in
            image
                .resizable()
            #if os(iOS)
                .renderingMode(.template)
            #endif
                .aspectRatio(contentMode: .fill)

        } placeholder: {
            ProgressView()
        }
    }
}

struct OrganizerImageView: View {
    let organizer: Organizer

    var body: some View {
        AsyncImage(url: organizer.imageURL) { image in
            image.resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            ProgressView()
        }
    }
}

struct EventIconImageView: View {
    var event: MusicEvent

    var body: some View {
        AsyncImage(url: event.iconImageURL) { image in
            image
                .resizable()
                #if os(iOS)
                .renderingMode(.template)
                #endif
                .aspectRatio(contentMode: .fill)

        } placeholder: {
            ProgressView()
        }
    }
}

struct ArtistImageView: View {
    var artist: Artist

    init(artist: Artist) {
        self.artist = artist
    }

    var body: some View {
        AsyncImage(url: artist.imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)

        } placeholder: {
            ProgressView()
        }
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
            id: -1,
            musicEventID: nil,
            sortIndex: 0,
            name: "",
            iconImageURL: nil,
            color: .init(0)
        )
    }
}

public extension Stage {
    struct IconView: View {
        public init(stageID: Stage.ID) {
//            _stage = FetchOne(
//                wrappedValue: .placeholder,
//                Stage.find(stageID)
//            )
            
        }

        // TODO: Replace @FetchOne with GRDB query
        var stage: Stage = .placeholder

        @Environment(\.colorScheme) var colorScheme

        public var body: some View {
            CachedAsyncImage(requests: [
                ImageRequest(
                    url: stage.iconImageURL,
                    processors: [
//                        .resize(width: 60, height: 60)
                    ]
                )
                .withPipeline(.images)

            ]) { image in
                image
                    .resizable()
                    #if os(iOS)
                    .renderingMode(.template)
                    #endif
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(alignment: .center)

            } placeholder: {
                Placeholder(stageName: stage.name)
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

    struct Legend: View {
        // TODO: Replace @FetchAll with GRDB query
        var stages: [Stage.ID] = []

        public var body: some View {
            HStack {
                ForEach(stages, id: \.self) {
                    Stage.IconView(stageID: $0)
                        .frame(square: 50)
                }
            }
        }
    }

}
