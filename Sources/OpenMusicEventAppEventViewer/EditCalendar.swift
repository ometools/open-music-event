import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
import SwiftUI

@Feature
public struct EditCalendar {
    public init() {}

    public struct FormValue: Equatable, Sendable {
        public init(
            name: String = "",
            description: String = "",
            heroImageURL: String = ""
        ) {
            self.name = name
            self.description = description
            self.heroImageURL = heroImageURL
        }

        init(calendar: OMERecord.Calendar) {
            self.name = calendar.name
            self.description = calendar.description ?? ""
            self.heroImageURL = calendar.images?.imageAsset(role: .hero)?.url?.absoluteString ?? ""
        }

        public var name: String
        public var description: String
        public var heroImageURL: String
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State: Identifiable {
        public init(calendarID: OMERecord.Calendar.ID) {
            self.calendarID = calendarID
            self.form = FormFeature.State(value: FormValue())
        }

        public let calendarID: OMERecord.Calendar.ID

        var draft: OMERecord.Calendar.Draft?
        var errorMessage: String?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var isSaving = false

        public var id: OMERecord.Calendar.ID { calendarID }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && form.canSubmit
        }

        var heroImageAsset: OMERecord.ImageAsset? {
            trimmedHeroImageURL.httpOrHTTPSURL.map(OMERecord.ImageAsset.calendarHero)
        }

        var navigationTitle: String {
            "Edit Calendar"
        }

        var submitButtonTitle: String {
            "Save"
        }

        fileprivate var trimmedHeroImageURL: String {
            form.value.heroImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    fileprivate struct SaveRequest: Sendable {
        init?(state: State, value: FormValue) {
            guard let draft = state.draft else { return nil }
            self.draft = draft
            self.description = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.heroImageURL = value.heroImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            self.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var draft: OMERecord.Calendar.Draft
        var description: String
        var heroImageURL: String
        var name: String

        var preparedDraft: OMERecord.Calendar.Draft {
            var draft = draft
            draft.name = name
            draft.description = description.isEmpty ? nil : description
            var images = (draft.images ?? []).filter { $0.role != .hero }
            if let heroURL = heroImageURL.httpOrHTTPSURL {
                images.append(.calendarHero(url: heroURL))
            }
            draft.images = images.isEmpty ? nil : images
            return draft
        }
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .form:
                break

            case let .formSubmitted(value):
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This calendar could not be loaded."
                    return
                }
                guard state.form.canSubmit else {
                    state.errorMessage = "Fix the highlighted fields."
                    return
                }
                guard let request = SaveRequest(state: state, value: value) else {
                    state.errorMessage = "This calendar could not be loaded."
                    return
                }

                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await database.write { db in
                            try OMERecord.Calendar.upsert {
                                request.preparedDraft
                            }
                            .execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save calendar."
                            $0.isSaving = false
                        }
                    }
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This calendar could not be loaded."
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }

            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let calendar = try database.read({ db in
                    try OMERecord.Calendar
                        .where { $0.id.eq(state.calendarID) }
                        .fetchOne(db)
                }) {
                    state.draft = calendar.editDraft
                    state.form = FormFeature.State(value: FormValue(calendar: calendar))
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.draft = OMERecord.Calendar.Draft(
                        id: state.calendarID,
                        name: "Events",
                        description: nil,
                        images: nil
                    )
                    state.form = FormFeature.State(value: FormValue(name: "Events"))
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                }
            } catch {
                state.errorMessage = "This calendar could not be loaded."
            }
        }
    }
}

private enum EditCalendarFormFieldID {
    static var heroImageURL: AnyHashable { AnyHashable(\EditCalendar.FormValue.heroImageURL) }
    static var name: AnyHashable { AnyHashable(\EditCalendar.FormValue.name) }
}

private extension EditCalendar.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a calendar name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            Self.Field(\.heroImageURL) {
                Validation(error: "Enter an http or https hero image URL.") { value in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty || value.httpOrHTTPSURL != nil
                }
            }
        }
    }
}

public struct EditCalendarView: View {
    @Bindable var store: StoreOf<EditCalendar>

    public init(store: StoreOf<EditCalendar>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                loadedForm
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "calendar",
                    description: "This calendar could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button(store.submitButtonTitle) {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
        .navigationTitle(store.navigationTitle)
    }

    private var loadedForm: some View {
        Form {
            Section("Calendar") {
                TextField("Name", text: $store.form.value.name)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                FormFieldValidationStatus(
                    validation: store.form.validation[EditCalendarFormFieldID.name]
                )

                TextField("Description", text: $store.form.value.description)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            }

            Section("Hero Image") {
                if let asset = store.heroImageAsset {
                    ImageAssetAsyncImage(
                        asset: asset,
                        cacheContext: nil,
                        contentMode: .fill
                    ) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.12))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                TextField("Image URL", text: $store.form.value.heroImageURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                FormFieldValidationStatus(
                    validation: store.form.validation[EditCalendarFormFieldID.heroImageURL]
                )
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private extension OMERecord.Calendar {
    var editDraft: OMERecord.Calendar.Draft {
        OMERecord.Calendar.Draft(
            id: id,
            name: name,
            description: description,
            images: images
        )
    }
}

private extension OMERecord.ImageAsset {
    static func calendarHero(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
    }
}

private extension String {
    var httpOrHTTPSURL: URL? {
        guard
            let url = URL(string: self),
            url.scheme == "http" || url.scheme == "https"
        else { return nil }

        return url
    }
}
