//
//  Command.swift
//  open-music-event
//
//  Created by Woodrow Melling on 12/2/25.
//

import Foundation


public protocol Command: Sendable {

    associatedtype PerformResult

    /// A short, localized, human-readable string that describes the app intent
    /// using a verb and a noun in title case.
    static var title: LocalizedStringResource { get }

    /// A description of the app intent that the system shows to people.
    static var description: LocalizedStringResource? { get }

    /// Performs the intent after resolving the provided parameters.
    ///
    /// In the body of this function, validate your parameters and provide the system
    /// with information about needed parameter values or user clarification.
    func perform() async throws -> Self.PerformResult

    /// Creates an app intent.
    init()
}


import Sharing

enum OMECommand {}

extension OMECommand {
    struct ToggleEditMode: Command {
        static var title: LocalizedStringResource { "Toggle Edit Mode" }
        static var description: LocalizedStringResource? { "Toggle between read only and edit mode" }

        init() {}

        func perform() async throws {
        }
    }
}
