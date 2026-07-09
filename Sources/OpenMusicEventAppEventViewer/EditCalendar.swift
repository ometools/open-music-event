import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventComponents
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
            description: String = ""
        ) {
            self.name = name
            self.description = description
        }

        init(calendar: OMERecord.Calendar) {
            self.name = calendar.name
            self.description = calendar.description ?? ""
        }

        public var name: String
        public var description: String
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State: Identifiable {
        public init(calendarID: OMERecord.Calendar.ID) {
            self.calendarID = calendarID
            self.form = FormFeature.State(value: FormValue())
            let cacheContext = LocalImageCacheContext(calendarID: calendarID)
            self.heroImagePicker = ImageAssetPicker.State(
                configuration: .calendarHero,
                cacheContext: cacheContext
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .calendarLogo,
                cacheContext: cacheContext
            )
        }

        public let calendarID: OMERecord.Calendar.ID

        var draft: OMERecord.Calendar.Draft?
        var errorMessage: String?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var heroImagePicker: ImageAssetPicker.State
        var isSaving = false
        var logoImagePicker: ImageAssetPicker.State

        public var id: OMERecord.Calendar.ID { calendarID }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && form.canSubmit
        }

        var navigationTitle: String {
            "Edit Calendar"
        }

        var submitButtonTitle: String {
            "Save"
        }

        func preparedDraft(
            value: FormValue
        ) throws -> (draft: OMERecord.Calendar.Draft, blobs: [LocalImageBlob]) {
            guard var draft = draft else {
                throw EditCalendarError.missingDraft
            }
            let preparedImages = try preparedImages(
                context: LocalImageCacheContext(calendarID: calendarID)
            )
            let description = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.description = description.isEmpty ? nil : description
            draft.images = preparedImages.images.isEmpty ? nil : preparedImages.images
            return (draft, preparedImages.blobs)
        }

        mutating func resetImagePickers() {
            let cacheContext = LocalImageCacheContext(calendarID: calendarID)
            heroImagePicker = ImageAssetPicker.State(
                configuration: .calendarHero,
                assets: draft?.images,
                cacheContext: cacheContext
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .calendarLogo,
                assets: draft?.images,
                cacheContext: cacheContext
            )
        }

        private func preparedImages(
            context: LocalImageCacheContext
        ) throws -> (images: [OMERecord.ImageAsset], blobs: [LocalImageBlob]) {
            var images = (draft?.images ?? []).filter {
                $0.role != .hero && $0.role != .logo
            }
            var blobs: [LocalImageBlob] = []

            for picker in [heroImagePicker, logoImagePicker] {
                let preparedImages = try picker.materializedImages(context: context)
                images.append(contentsOf: preparedImages.images)
                blobs.append(contentsOf: preparedImages.blobs)
            }

            return (images, blobs)
        }
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case heroImagePicker(ImageAssetPicker.Action)
        case logoImagePicker(ImageAssetPicker.Action)
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
        Scope(\.heroImagePicker, action: \.heroImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.logoImagePicker, action: \.logoImagePicker) {
            ImageAssetPicker()
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
                let preparedDraft: (draft: OMERecord.Calendar.Draft, blobs: [LocalImageBlob])
                do {
                    preparedDraft = try state.preparedDraft(value: value)
                } catch {
                    state.errorMessage = "Unable to save calendar."
                    return
                }
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await database.write { db in
                            try OMERecord.Calendar.upsert {
                                preparedDraft.draft
                            }
                            .execute(db)
                            if !preparedDraft.blobs.isEmpty {
                                try LocalImageBlob.insert { preparedDraft.blobs }.execute(db)
                            }
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

            case .heroImagePicker, .logoImagePicker:
                break

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
                    state.resetImagePickers()
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
                    state.resetImagePickers()
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
    static var name: AnyHashable { AnyHashable(\EditCalendar.FormValue.name) }
}

private enum EditCalendarError: Error {
    case missingDraft
}

private extension EditCalendar.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a calendar name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
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

            ImageAssetPickerSection(
                store: store.scope(\.heroImagePicker, action: \.heroImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker, action: \.logoImagePicker)
            )

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
