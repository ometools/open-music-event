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

extension Organizer {
    struct IconView: View {
        let organizer: Organizer

        var body: some View {
//            CachedAsyncImage(
//                requests: [
//                    ImageRequest(
//                        url: organizer.iconImageURL,
//                        processors: [.resize(width: 440)]
//                    ).withPipeline(.images)
//                ]
//            ) {
//                $0.resizable().renderingMode(.template)
//            } placeholder: {
//                #if !SKIP
//                AnimatedMeshView()
//                    .overlay(Material.thinMaterial)
//                    .opacity(0.25)
//                #else
//                ProgressView().frame(square: 440)
//                #endif
//
//            }
//            .frame(maxWidth: .infinity)
        }
    }

    struct ImageView: View {
        let organizer: Organizer

        var body: some View {
//            CachedAsyncImage(
//                requests: [
//                    ImageRequest(
//                        url: organizer.imageURL,
//                        processors: [.resize(width: 440)]
//                    ).withPipeline(.images)
//                ]
//            ) {
//                $0.resizable().renderingMode(.original)
//            } placeholder: {
//                #if !SKIP
//                AnimatedMeshView()
//                    .overlay(Material.thinMaterial)
//                    .opacity(0.25)
//                #else
//                ProgressView().frame(square: 440)
//                #endif
//
//            }
//            .frame(maxWidth: .infinity)
        }
    }
}

extension MusicEvent {
    struct IconImageView: View {
        var event: MusicEvent
        
        var body: some View {
//            CachedAsyncImage(
//                requests: [
//                    ImageRequest(
//                        url: event.iconImageURL,
//                        processors: [
//                            .resize(size: CGSize(width: 60, height: 60))
//                        ]
//                    )
//                    .withPipeline(.images)
//                ]
//            ) {
//                $0
//                    .renderingMode(.template)
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//            } placeholder: {
//                if event.iconImageURL != nil {
//                    ProgressView()
//                } else {
//                    Image(systemName: "x.circle").foregroundStyle(.red)
//                }
//
//            }
//            .frame(width: 60, height: 60)
//            .clipped()
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
//            GeometryReader { geo in
//                CachedAsyncImage(
//                    requests: [
//                        ImageRequest(
//                            url: imageURL,
//                            processors: [
//                                .resize(size: geo.size)
//                            ]
//                        )
//                        .withPipeline(.images)
//                    ]
//                ) {
//                    $0.resizable()
//                        .aspectRatio(contentMode: .fill)
//                } placeholder: {
//                    Image(systemName: "person.fill")
//                        .resizable()
//                        .frame(square: 30)
//                }
//            }
//            .clipped()
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
//            // TODO: Needs
//            CachedAsyncImage(requests: [
//                ImageRequest(
//                    url: stage.iconImageURL,
//                    processors: [
//                        .resize(size: CGSize(width: 60, height: 60))
//                    ],
//                    priority: .veryHigh // There are very few stage images, and they are often very required for best UI.
//                )
//                .withPipeline(.images)
//
//            ]) { @MainActor image in
//                image
//                    .resizable()
//                    .renderingMode(.template)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .frame(alignment: .center)
//
//            } placeholder: {
//                Placeholder(stageName: stage.name)
//            }
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
