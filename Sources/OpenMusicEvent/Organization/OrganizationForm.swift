//
//  OrganizationForm.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/11/25.
//

import  SwiftUI; import SkipFuse
import CasePaths
import Dependencies
import CoreModels
import IssueReporting

struct OrganizationFormView: View {
    @Observable
    @MainActor
    class Model: Identifiable {
        let id = UUID()

        @CasePathable
        enum GithubConfigType: CaseIterable, Hashable {
            case branch
            case version
            case url

            var label: LocalizedStringKey {
                switch self {
                case .branch: "branch"
                case .version: "version"
                case .url: "url"
                }
            }
        }

        var githubURL = "https://github.com/woodymelling/shambhala-ome"
        var githubConfigType: GithubConfigType = .branch
        var branchText = "main"
        var versionText = ""

        var isLoading = false
        var dismiss = ViewTrigger()
        var errorMessage: String?


        var repositoryLocation: OrganizationReference? {
            guard let url = URL(string: githubURL)
            else { return nil }

            let cleanedURL = url.deletingPathExtension()

            switch githubConfigType {
            case .branch:
                guard !branchText.isEmpty else { return nil }
                return .repository(OrganizationReference.Repository(baseURL: cleanedURL, version: .branch(branchText)))
            case .version:
                guard let version = SemanticVersion(versionText) else { return nil }
                return .repository(OrganizationReference.Repository(baseURL: cleanedURL, version: .version(version)))
            case .url:
                return OrganizationReference.url(url)
            }
        }

        func didTapSave() async {
            self.errorMessage = nil
            
            guard let repositoryLocation
            else {
                errorMessage = "Invalid Repository URL"
                return
            }

            self.isLoading = true
            do {
                try await downloadAndStoreOrganizer(from: repositoryLocation)
            } catch {
                self.errorMessage = error.localizedDescription
                reportIssue(error)
            }
            self.dismiss.trigger()
            self.isLoading = false

        }
    }

    @Bindable var store = Model()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                TextField(
                    "Organization URL",
                    text: $store.githubURL,
                    prompt: Text("github.com/your-organization/ome-config")
                )
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .textContentType(.URL)
                #endif

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            HStack {
                switch store.githubConfigType {
                case .branch:
                    TextField("Branch Name", text: $store.branchText)
                case .version:
                    TextField("Version", text: $store.versionText)
                case .url:
                    EmptyView()
                }

                Picker("", selection: $store.githubConfigType) {
                    ForEach(Model.GithubConfigType.allCases, id: \.self) { configReference in
                        Text(configReference.label)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            if store.isLoading {
                ProgressView()
            } else {
                Button {
                    Task {
                        await store.didTapSave()
                    }
                } label: {
                    Text("Add")
                }
            }
        }
        .onTrigger(of: store.dismiss) {
            dismiss()
        }
    }
}
//
//
//#Preview {
//    Text("Hello World")
//        .sheet(isPresented: .constant(true)) {
//            NavigationStack {
//                OrganizationFormView()
//                    .navigationTitle("Add Organization")
//            }
//        }
//}


struct ViewTrigger: Equatable, Sendable {
    private var value = 0
    mutating func trigger() {
        value += 1
    }
}

extension View {
    func onTrigger(of viewTrigger: ViewTrigger, operation: @escaping () -> Void) -> some View {
        self.onChange(of: viewTrigger) { _, _ in
            operation()
        }
    }
}
