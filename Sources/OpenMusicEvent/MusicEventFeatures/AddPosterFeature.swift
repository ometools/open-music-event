//
//  AddPosterFeature.swift
//  open-music-event
//
//  Created by Assistant on 2/25/26.
//

import SwiftUI
import Observation
import Dependencies

@Observable
@MainActor
public final class AddPosterFeature: Identifiable {
    public init() {

    }

    public let id = "1"

    var title: String = "lineup"
    var imageURLString: String = "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/wicked-woods-2025%2Flineup-poster.webp?alt=media&token=77b1d177-3289-4891-8c8a-2badf33b2960"

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    func create() {
        guard let url = URL(string: imageURLString), !imageURLString.isEmpty else { return }

        let poster = Poster.Draft(
            id: .init(stabilizedBy: title),
            musicEventID: self.musicEventID,
            title: self.title.nilIfEmpty,
            imageURL: url
        )

        withErrorReporting {
            try defaultDatabase.write { db in
                try poster.upsert(db)
            }
        }

    }
}

public struct AddPosterFeatureView: View {
    @Bindable var store: AddPosterFeature
    @Environment(\.dismiss) var dismiss

    public init(store: AddPosterFeature) { self.store = store }

    public var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $store.title)
            }

            Section("Image") {
                TextField("Image URL", text: $store.imageURLString)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
            }
        }
        .navigationTitle("New Poster")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.create()
                    dismiss()
                }
                .disabled(URL(string: store.imageURLString) == nil)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

//#Preview {
//    NavigationStack {
//        AddPosterFeatureView(store: .init())
//    }
//}
