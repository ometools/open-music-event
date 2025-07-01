//
//  ZipClient.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/17/25.
//

import DependenciesMacros
import Dependencies
import Foundation
import Zip

@DependencyClient
struct ZipClient: Sendable {
    var unzipFile: @Sendable (_ source: URL, _ destination: URL) throws -> Void
}

extension ZipClient: DependencyKey {
    static let testValue = ZipClient()
    static let liveValue = ZipClient { source, destination in
        Zip.addCustomFileExtension("tmp")
        try Zip.unzipFile(source, destination: destination)
    }
}
