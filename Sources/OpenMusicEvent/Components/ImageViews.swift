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
        } placeholder: {
            ProgressView()
        }
    }
}

extension Artist {
    struct ImageView: View {

        // TODO: Replace @FetchOne with GRDB query
        var imageURL: URL?

        init(artistID: Artist.ID) {
            // TODO: Replace FetchOne with GRDB query
            // self._imageURL = FetchOne(wrappedValue: nil, Artist.find(artistID).select { $0.imageURL })
            self.imageURL = nil
        }

        var body: some View {
            CachedAsyncImage(
                requests: [
                    ImageRequest(
                        url: imageURL,
                        processors: []
                    )
                    .withPipeline(.images)
                ]
            ) {
                $0.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.fill")
                    .resizable()
                    .frame(square: 30)
            }
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
