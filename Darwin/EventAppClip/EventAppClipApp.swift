//
//  EventAppClipApp.swift
//  EventAppClip
//
//  Created by Woodrow Melling on 3/21/26.
//

import SwiftUI
import OpenMusicEvent
import Dependencies
import IssueReporting
import OSLog

let logger = Logger(
    subsystem: "bundle.ome.OpenMusicEvent",
    category: "App Clip"
)

@main
struct EventAppClipApp: App {

    init() {
        #if APPCLIP
        print("APP CLIP")
        #endif

        prepareDependencies {
            $0.resolveOrgID = .init { id in
                if id == "wicked-woods" {
                    return .zipURL(URL(string: "https://d1s8fi0p4o2ghp.cloudfront.net/wicked-woods-ome.zip")!)
                } else {
                    struct OrganizationNotFoundError: Error {}
                    throw OrganizationNotFoundError()
                }
            }
        }

        withErrorReporting {
            try OME.prepareDependencies(enableFirebase: false)
        }
    }


    static let appClipStore = AppClip()


    var body: some Scene {
        WindowGroup {
            OMEAppEntryPoint(store: EventAppClipApp.appClipStore.entryPoint)
                .onOpenURLWhenSceneActive { url in
                    EventAppClipApp.appClipStore.onOpenURLWhenSceneActive(url: url)
                }
        }
    }
}

import URLRouting

@MainActor
@Observable
class AppClip {
    let entryPoint = OMEAppEntryPoint.Model()

    func onOpenURLWhenSceneActive(url: URL) {
        logger.info("AppClip.onOpenURLWhenSceneActive: \(url)")
        entryPoint.didReceiveURL(url: url)
    }
}
