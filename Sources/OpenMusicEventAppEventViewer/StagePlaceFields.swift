import ComposableArchitecture2
import Foundation
import OpenMusicEventLexicon
import SwiftUI

struct StagePlaceLocatorEditor: View {
    @Bindable var store: StoreOf<EditStage>

    var body: some View {
        Section("Locators") {
            ForEach(store.form.value.locators) { locator in
                HStack {
                    Text(locator.kind.title)
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLocatorButtonTapped(locator.id)) }
                        Button("Move Up") { store.send(.moveLocatorButtonTapped(locator.id, -1)) }
                            .disabled(store.form.value.locators.first?.id == locator.id)
                        Button("Move Down") { store.send(.moveLocatorButtonTapped(locator.id, 1)) }
                            .disabled(store.form.value.locators.last?.id == locator.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLocatorButtonTapped(locator.id))
                        }
                    } label: {
                        Label("Locator Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Menu("Add Locator") {
                Button("Address") { store.send(.addLocatorButtonTapped(.address)) }
                Button("Coordinates") { store.send(.addLocatorButtonTapped(.geo)) }
                Button("Foursquare Place") { store.send(.addLocatorButtonTapped(.foursquare)) }
                Button("H3 Cell") { store.send(.addLocatorButtonTapped(.hthree)) }
            }
        }
        if let index = store.form.value.locators.firstIndex(where: { $0.id == store.editingLocatorID }) {
            Section("Edit Locator") {
                EditableLocatorFields(locator: $store.form.value.locators[index])
            }
        }
    }
}

struct StagePlaceLinkEditor: View {
    @Bindable var store: StoreOf<EditStage>

    var body: some View {
        Section("Links") {
            ForEach(store.form.value.links) { link in
                HStack {
                    Text(link.title.isEmpty ? (link.url.isEmpty ? "New Link" : link.url) : link.title)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLinkButtonTapped(link.id)) }
                        Button("Move Up") { store.send(.moveLinkButtonTapped(link.id, -1)) }
                            .disabled(store.form.value.links.first?.id == link.id)
                        Button("Move Down") { store.send(.moveLinkButtonTapped(link.id, 1)) }
                            .disabled(store.form.value.links.last?.id == link.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLinkButtonTapped(link.id))
                        }
                    } label: {
                        Label("Link Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Button("Add Link") { store.send(.addLinkButtonTapped) }
        }
        if let index = store.form.value.links.firstIndex(where: { $0.id == store.editingLinkID }) {
            Section("Edit Link") {
                EditLinkFields(link: $store.form.value.links[index])
            }
        }
    }
}

struct StagePlaceLineupEditor: View {
    @Bindable var store: StoreOf<EditStage>

    var body: some View {
        Section("Stage Lineup") {
            ForEach(store.form.value.lineup.indices, id: \.self) { index in
                let id = store.form.value.lineup[index]
                HStack {
                    Text(store.contributors.first(where: { $0.id == id })?.name ?? "Unavailable contributor")
                    Spacer()
                    Menu {
                        Button("Move Up") { store.send(.moveLineupContributorTapped(id, -1)) }
                            .disabled(index == 0)
                        Button("Move Down") { store.send(.moveLineupContributorTapped(id, 1)) }
                            .disabled(index == store.form.value.lineup.count - 1)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLineupContributorTapped(id))
                        }
                    } label: {
                        Label("Contributor Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Menu("Add Contributor") {
                ForEach(store.contributors.filter { !store.form.value.lineup.contains($0.id) }) { contributor in
                    Button(contributor.name) {
                        store.send(.addLineupContributorTapped(contributor.id))
                    }
                }
            }
            .disabled(store.contributors.allSatisfy { store.form.value.lineup.contains($0.id) })
        }
    }
}

struct StagePlaceIdentityEditor: View {
    @Bindable var store: StoreOf<EditStage>

    var body: some View {
        Section("Persistent Stage") {
            if let id = store.form.value.persistentStageID {
                LabeledContent("Linked Stage") {
                    Text(store.persistentStages.first(where: { $0.id == id })?.name ?? "Unavailable stage")
                }
                Button("Unlink Stage", role: .destructive) {
                    store.send(.unlinkPersistentStageTapped)
                }
            }
            if store.persistentStages.isEmpty {
                Text("No persistent stage profiles available")
                    .foregroundStyle(.secondary)
            } else {
                Menu(store.form.value.persistentStageID == nil ? "Link Stage" : "Change Stage") {
                    ForEach(store.persistentStages) { stage in
                        Button(stage.name) {
                            store.send(.linkPersistentStageTapped(stage.id))
                        }
                    }
                }
            }
        }
    }
}

struct StagePlaceLocatorDetails: View {
    let place: EventPlace

    @ViewBuilder
    var body: some View {
        if let locators = place.locators, !locators.isEmpty {
            Section("Locators") {
                ForEach(locators.indices, id: \.self) { index in
                    let locator = EditableLocator(locators[index])
                    LabeledContent(locator.kind.title) {
                        Text(locator.displayValue)
                    }
                }
            }
        }
    }
}

struct StagePlaceLinkDetails: View {
    let place: EventPlace

    @ViewBuilder
    var body: some View {
        if let links = place.links, !links.isEmpty {
            Section("Links") {
                ForEach(links.indices, id: \.self) { index in
                    let link = links[index]
                    Link(destination: link.url) {
                        Text(link.title ?? link.url.absoluteString)
                    }
                }
            }
        }
    }
}

private extension EditableLocator {
    var displayValue: String {
        switch kind {
        case .address:
            return [street, locality, region, postalCode, country]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        case .geo:
            return "\(latitude), \(longitude)"
        case .foursquare:
            return fsqPlaceID
        case .hthree:
            return hthreeValue
        case .unknown:
            return "Other locator"
        }
    }
}
