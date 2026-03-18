//
//  PostersFeature.swift
//  open-music-event
//
//  Created by Woodrow Melling on 2/25/26.
//

import SwiftUI
import Observation
import Dependencies
import GRDB

@Observable
@MainActor
public class PostersFeature {
    init() { }

    var posters: [Poster] = []

    var addPoster: AddPosterFeature?

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    var selectedPoster: Poster.ID?

    func didTapCreatePoster() {
        withDependencies(from: self) {
            self.addPoster = .init()
        }
    }

    func didTapDeletePoster(_ id: Poster.ID) {
        _ = withErrorReporting {
            try defaultDatabase.write { db in
                try Poster.deleteOne(db, id: id)
            }
        }
    }

    func task() async {
        let musicEventID = musicEventID
        let query = ValueObservation.tracking { db in
            try Poster
                .filter(Column("musicEventID") == musicEventID)
                .fetchAll(db)
        }

        await withErrorReporting {
            for try await posters in query.values(in: defaultDatabase) {
                self.posters = posters
            }
        }
    }

    var showCreatePosterButton: Bool {
        true
    }

    var showingDeleteButton: Bool {
        true
    }
}

public struct PostersFeatureView: View {
    @Bindable var store: PostersFeature

    public var body: some View {
        Group {
            if store.posters.isEmpty {
                ContentUnavailableView {
                    Label("No Posters", systemImage: "photo.on.rectangle")
                } actions: {
                    if store.showCreatePosterButton {
                        Button {
                            store.didTapCreatePoster()
                        } label: {
                            Label("Create Poster", systemImage: "plus")
                        }
                    }
                }
            } else {
                TabView(selection: $store.selectedPoster) {
                    ForEach(store.posters) { poster in
                        PosterView(poster: poster, store: store)
                    }
                }
                .tabViewStyle(.page)
            }
        }
        .toolbar {
            if store.showCreatePosterButton {
                Button {
                    store.didTapCreatePoster()
                } label: {
                    Label("Create Poster", systemImage: "plus")
                }
            }
        }
        .sheet(item: $store.addPoster) { store in
            NavigationStack {
                AddPosterFeatureView(store: store)
            }
        }
        .task { await store.task() }
    }


    struct PosterView: View {
        let poster: Poster
        let store: PostersFeature

        @State var toolbarVisibility: Visibility = .visible

        var body: some View {
            CachedAsyncImage(url: poster.imageURL)
                ._zoomable()
                .omeContextMenu {
                    if store.showingDeleteButton {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.didTapDeletePoster(poster.id)
                        }
                    }
                }
                .tag(poster.id)
        }
    }

}
//
//#Preview("Empty - View Mode") {
//    let store = PostersFeature()
//    return NavigationStack {
//        PostersFeatureView(store: store)
//    }
//}
//
//#Preview("Empty - Edit Mode") {
//
//    let store = PostersFeature()
//    return NavigationStack {
//        PostersFeatureView(store: store)
//            .environment(\.editMode, .constant(.active))
//    }
//}
//
//#Preview("With Posters") {
//    let store = PostersFeature()
//    // TODO: Replace with real Poster initializers if available
//    // Assuming Poster conforms to Identifiable and has imageURL
//    // store.posterURLs = [Poster(...), Poster(...)]
//    return NavigationStack {
//        PostersFeatureView(store: store)
//    }
//}
//
//#Preview("Create Flow") {
//    let store = PostersFeature()
//    return PostersFeatureView(store: store)
//}
