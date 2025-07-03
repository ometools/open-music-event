//
//  ImagePrefetchClient.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/21/25.
//

import Dependencies
import DependenciesMacros
import GRDB
import IssueReporting

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
            // TODO: Replace @FetchAll with GRDB query
            // @FetchAll(Current.stages) var stages
            // try? await $stages.sharedReader.load()
            let stages: [Stage] = []

            await withTaskGroup {
                for stage in stages {
                    if let imageURL = stage.iconImageURL {
                        $0.addTask {
                            await withErrorReporting {
                                #if os(iOS)
                                _ = try await ImagePipeline.images.image(for: imageURL)
                                #endif
                            }
                        }
                    }
                }

                await $0.waitForAll()
            }
        },
        prefetchArtistImages: {
            // TODO: Replace @FetchAll with GRDB query
            // @FetchAll(Current.artists) var artists
            // try? await $artists.sharedReader.load()
            let artists: [Artist] = []

            await withTaskGroup {
                for artist in artists {
                    if let imageURL = artist.imageURL {
                        $0.addTask {
                            await withErrorReporting {
                                #if os(iOS)
                                _ = try await ImagePipeline.images.image(for: imageURL)
                                #endif
                            }
                        }
                    }
                }

                await $0.waitForAll()
            }
        }


    )
}
