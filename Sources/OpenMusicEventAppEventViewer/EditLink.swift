import ATProtoTypes
import Foundation
import OpenMusicEventComponents
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct EditableLink: Identifiable, Equatable {
    public var id = UUID()
    var original: OME.Link?
    var title = ""
    var platformRawValue = ""
    var description = ""
    var roleChoice = ""
    var url = ""
    var useChoice = ""

    init() {}

    init(_ link: OME.Link) {
        self.original = link
        self.title = link.title ?? ""
        self.platformRawValue = link.platformIdentifier ?? ""
        self.description = link.description ?? ""
        self.url = link.url.absoluteString
        switch link.role {
        case .known(.website): self.roleChoice = "website"
        case .known(.tickets): self.roleChoice = "tickets"
        case .known(.contact(let contact)):
            self.roleChoice = "contact"
            self.useChoice = Self.useChoice(for: contact.use)
        case .known(.reporting(let reporting)):
            self.roleChoice = "reporting"
            self.useChoice = Self.useChoice(for: reporting.use)
        case .unknown: self.roleChoice = "unknown"
        case nil: break
        }
    }

    var preparedLink: OME.Link? {
        guard validationMessage == nil, let url = URL(string: trimmedURL) else { return nil }
        var link = original ?? OME.Link(url: url)
        if self.url != original?.url.absoluteString { link.url = url }
        if title != (original?.title ?? "") { link.title = trimmedTitle.isEmpty ? nil : trimmedTitle }
        if description != (original?.description ?? "") {
            link.description = trimmedDescription.isEmpty ? nil : trimmedDescription
        }
        let initialChoices = original.map(Self.init)
        if roleChoice != (initialChoices?.roleChoice ?? "") || useChoice != (initialChoices?.useChoice ?? "") {
            switch roleChoice {
            case "": link.role = nil
            case "website": link.role = .known(.website(.init()))
            case "tickets": link.role = .known(.tickets(.init()))
            case "contact": link.role = .known(.contact(.init(use: preparedUse)))
            case "reporting": link.role = .known(.reporting(.init(use: preparedUse)))
            case "unknown":
                guard let originalRole = original?.role, case .unknown = originalRole else { return nil }
            default: return nil
            }
        }
        if platformRawValue != (original?.platformIdentifier ?? "") {
            if let platform = ExternalPlatform(rawValue: trimmedPlatformRawValue) {
                link.platform = .known(platform)
            } else if trimmedPlatformRawValue.isEmpty {
                link.platform = nil
            }
        }
        return link
    }

    var validationMessage: String? {
        guard !trimmedURL.isEmpty else { return "Enter a link URL or delete this link." }
        guard URL(string: trimmedURL)?.scheme != nil else { return "Enter a valid link URL." }
        if !["", "website", "tickets", "contact", "reporting", "unknown"].contains(roleChoice) {
            return "Choose a valid link purpose."
        }
        if roleChoice == "unknown" {
            guard let originalRole = original?.role, case .unknown = originalRole else {
                return "Choose a valid link purpose."
            }
        }
        if !trimmedPlatformRawValue.isEmpty,
           ExternalPlatform(rawValue: trimmedPlatformRawValue) == nil,
           original?.platformIdentifier != trimmedPlatformRawValue {
            return "Choose a valid link platform."
        }
        return nil
    }

    private static func useChoice(for use: Open<OME.Link.ContactUse>?) -> String {
        switch use {
        case .known(.emergency): "emergency"
        case .known(.nonEmergency): "nonEmergency"
        case .unknown(let value): value.string ?? ""
        case nil: ""
        }
    }

    private var preparedUse: Open<OME.Link.ContactUse>? {
        switch useChoice {
        case "": nil
        case "emergency": .known(.emergency)
        case "nonEmergency": .known(.nonEmergency)
        default: .unknown(.string(useChoice))
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPlatformRawValue: String { platformRawValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct EditLinkFields: View {
    @Binding var link: EditableLink

    var body: some View {
        TextField("Title", text: $link.title)
        TextField("URL", text: $link.url)
        #if os(iOS)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #endif
        PortableTextField("Description", text: $link.description, axis: .vertical)
            .portableLineLimit(2...5)
        Picker("Purpose", selection: $link.roleChoice) {
            Text("Unspecified").tag("")
            Text("Website").tag("website")
            Text("Tickets").tag("tickets")
            Text("Contact").tag("contact")
            Text("Reporting").tag("reporting")
            if link.roleChoice == "unknown" {
                Text("Other (preserved)").tag("unknown")
            }
        }
        if link.roleChoice == "contact" || link.roleChoice == "reporting" {
            Picker("Use", selection: $link.useChoice) {
                Text("Unspecified").tag("")
                Text("Emergency").tag("emergency")
                Text("Non-Emergency").tag("nonEmergency")
                if !["", "emergency", "nonEmergency"].contains(link.useChoice) {
                    Text("Other (preserved)").tag(link.useChoice)
                }
            }
        }
        Picker("Platform", selection: $link.platformRawValue) {
            Text("Auto").tag("")
            ForEach(ExternalPlatform.allCases, id: \.rawValue) { platform in
                Text(verbatim: platform.name).tag(platform.rawValue)
            }
            if !link.platformRawValue.isEmpty,
               ExternalPlatform(rawValue: link.platformRawValue) == nil {
                Text("Other (preserved)").tag(link.platformRawValue)
            }
        }
    }
}
