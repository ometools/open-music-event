import  SwiftUI; import SkipFuse
// import SharingGRDB
import Dependencies
import GRDB
import Observation
import CoreModels
import OpenMusicEventParser


@MainActor
@Observable
final class MoreTabFeature {
    // TODO: Replace @FetchOne with GRDB query
    var organizer: Organizer = .init(url: URL.temporaryDirectory, name: "")

    // TODO: Replace @FetchOne with GRDB query
    var musicEvent: MusicEvent?

    var isLoadingOrganizer = false
    var errorMessage: String?

    func didTapReloadOrganizer() async {
        guard let currentOrganizerID = musicEvent?.organizerURL
        else { return }
        self.errorMessage = nil

        self.isLoadingOrganizer = true

        do {
            try await downloadAndStoreOrganizer(from: .url(currentOrganizerID))
            self.isLoadingOrganizer = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoadingOrganizer = true

        }
    }

    func didTapExitEvent() {
        NotificationCenter.default.post(name: .userRequestedToExitEvent, object: nil)
    }
}

struct MoreView: View {
    let store: MoreTabFeature

    var body: some View {
        List {

            NavigationLink {
                AboutAppView(store: store)
            } label: {
                Label("About", systemImage: "info.circle")
            }

        }
        .navigationTitle("More")
    }
}


struct AboutAppView: View {
    let store: MoreTabFeature
    var body: some View {
        List {
            Section(store.musicEvent?.name ?? "") {
                Button {
                    Task {
                        await store.didTapReloadOrganizer()
                    }
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("Update to the newest schedule", systemImage: "arrow.clockwise")
                            Spacer()
                            if store.isLoadingOrganizer {
                                ProgressView()
                            }
                        }

                        if let errorMessage = store.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button("Exit and see previous events", systemImage: "door.left.hand.open") {
                    store.didTapExitEvent()
                }
            }

            Section("Open Music Event") {
                Text("""
                OME (Open Music Event) is designed to help festival attendees effortlessly get access to information that they need during an event. The main goal of this project is to give concert and festival goers a simple, intuitive way to get information about events they are attending.
                
                The secondary goal is providing a free and open source way for event organizers to create, maintain and update information about their event.
                
                If you have any suggestions or discover any issues, please start a discussion and they will be addressed as soon as possible.
                """)

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Suggest a feature", systemImage: "plus.bubble")
                }
            }
        }
        .navigationTitle("About")
    }
}

//
//#Preview("About App") {
//
//    prepareDependencies {
//        $0.defaultDatabase = try! appDatabase()
//    }
//
//    return NavigationStack {
//        AboutAppView(store: .init())
//    }
//}
