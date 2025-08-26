//
//  AboutAppView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 8/25/25.
//

import SwiftUI

struct AboutAppView: View {
    let store: MusicEventFeatures
    var body: some View {
        List {
            Section(store.event.name) {
                Button {
                    Task {
                        await store.didTapReloadOrganizer()
                    }
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("Update to the newest schedule", image: Icons.arrowClockwise)
                            Spacer()
                            if store.isLoadingOrganizer {
                                ProgressView()
                            }
                        }

                        if let errorMessage = store.errorMessage {
                            Label(errorMessage, image: Icons.exclamationmarkCircleFill)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button {
                    store.didTapExitEvent()
                } label: {
                    Label("Exit and see previous events", image: Icons.doorLeftHandOpen)
                }
            }

            Section("Open Music Event") {
                Text("""
                OME (Open Music Event) is designed to help festival attendees effortlessly get access to information that they need during an event. The main goal of this project is to give concert and festival goers a simple, intuitive way to get information about events they are attending.
                
                The secondary goal is providing a free and open source way for event organizers to create, maintain and update information about their event.
                
                If you have any suggestions or discover any issues, please start a discussion and they will be addressed as soon as possible.
                """)

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event")!) {
                    Label {
                        Text("GitHub")
                    } icon: {
                        Icons.github.frame(square: 25)
                    }
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Report an Issue", image: Icons.exclamationmarkBubble)
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/discussions/new")!) {
                    Label("Suggest a feature", image: Icons.plusBubble)
                }
            }

            NavigationLink("Logs") {
                LogsView()
            }
        }
        .navigationTitle("About")
    }
}


struct LogsView: View {
    let issueReporter = InMemoryIssueReporter.shared
//
//    var text: String {
//        issueReporter.issues.joined(separator: "\n")
//    }

    var body: some View {
        List {
            Section("Issues") {
                ForEach(issueReporter.issues) { issue in
                    Text(issue.message)
                        .foregroundColor(.red)
                }

                Button("Copy issues") {
                    UIPasteboard.general.string = issueReporter.issues.map { $0.message }.joined(separator: "\n")
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Report this issue", image: Icons.exclamationmarkBubble)

                }
            } footer: {
                Text("Please copy these issues and report it if you're having problems. Github will be the best place for me to track it, but you can also send me an email at woodymelling@gmail.com")
            }

        }
        .navigationTitle("Logs")
    }
}
