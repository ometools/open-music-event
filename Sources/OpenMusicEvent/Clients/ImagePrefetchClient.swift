//
//  ImagePrefetchClient.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/21/25.
//

import Sharing
import Dependencies
import DependenciesMacros
import ImageCaching
import SharingGRDB

@DependencyClient
struct ImagePrefetchClient: Sendable {
    var prefetchStageImages: @Sendable () async throws -> Void
    var prefetchArtistImages: @Sendable () async throws -> Void
}

extension DependencyValues {
    var imagePrefetchClient: ImagePrefetchClient {
        get { self[ImagePrefetchClient.self] }
        set { self[ImagePrefetchClient.self] = newValue }
    }
}

extension ImagePrefetchClient: DependencyKey {
    static let testValue = Self()
    static let noop = ImagePrefetchClient(prefetchStageImages: {}, prefetchArtistImages: {})

    static let liveValue = ImagePrefetchClient(
        prefetchStageImages: {
            @FetchAll(Current.stages) var stages
            try? await $stages.sharedReader.load()

            await withTaskGroup {
                for stage in stages {
                    if let imageURL = stage.iconImageURL {
                        $0.addTask {
                            await withErrorReporting {
                                _ = try await ImagePipeline.images.image(for: imageURL)
                            }
                        }
                    }
                }

                await $0.waitForAll()
            }
        },
        prefetchArtistImages: {
            @FetchAll(Current.artists) var artists
            try? await $artists.sharedReader.load()

            await withTaskGroup {
                for artist in artists {
                    if let imageURL = artist.imageURL {
                        $0.addTask {
                            await withErrorReporting {
                                _ = try await ImagePipeline.images.image(for: imageURL)
                            }
                        }
                    }
                }

                await $0.waitForAll()
            }
        }


    )
}
