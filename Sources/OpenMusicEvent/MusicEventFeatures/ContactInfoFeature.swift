//
//  ContactInfoFeature.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//


//
//  SwiftUIView.swift
//  
//
//  Created by Woodrow Melling on 5/21/22.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels
import Dependencies

// TODO: Replace with GRDB query
// extension Optional where Wrapped == MusicEvent {
//     static var current: Where<Self> {
//         @Dependency(\.musicEventID) var musicEventID
//         return MusicEvent?.find(musicEventID)
//     }
// }


@MainActor
@Observable
public class ContactInfoFeature {

    // TODO: Replace @FetchOne with GRDB query
    var contactNumbers: [MusicEvent.ContactNumber] = []

    func didTapContactNumber(_ contactNumber: MusicEvent.ContactNumber) async {
        #if os(iOS)
        @Dependency(\.openURL) var openURL
        guard let url = URL(string: "tel:\(contactNumber.phoneNumber)")
        else { return }

        await openURL(url)
        #elseif os(Android)
        fatalError("TODO")
        #endif
    }
}

struct ContactInfoView: View {
    let store: ContactInfoFeature

    var body: some View {
        List {
            ForEach(store.contactNumbers, id: \.phoneNumber) { contactNumber in
                Button {
                    Task {
                        await store.didTapContactNumber(contactNumber)
                    }
                } label: {

                    HStack {

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contactNumber.title)
                                .font(.headline)
                            Text(contactNumber.phoneNumber.asPhoneNumber)
                            #if os(iOS)
                                .textSelection(.enabled)
                            #endif

                            if let description = contactNumber.description {
                                Text(description)
                                    .font(.caption)
                            }
                        }

                        Spacer()

                        Image(systemName: "phone.fill")
                            .resizable()
                            .frame(square: 20)
                            .foregroundColor(.accentColor)

                    }
                    .padding()

                }
                .buttonStyle(.plain)

            }
        }
        .navigationTitle("Contact Info")
    }
}

extension String {
    var asPhoneNumber: String {
        self.applyPatternOnNumbers(pattern: "(###) ###-####", replacementCharacter: "#")
    }

    func applyPatternOnNumbers(pattern: String, replacementCharacter: Character) -> String {
        var pureNumber = self.replacingOccurrences( of: "[^0-9]", with: "", options: .regularExpression)
        for index in 0 ..< pattern.count {
            guard index < pureNumber.count else { return pureNumber }
            let stringIndex = String.Index(utf16Offset: index, in: pattern)
            let patternCharacter = pattern[stringIndex]
            guard patternCharacter != replacementCharacter else { continue }
            pureNumber.insert(patternCharacter, at: stringIndex)
        }
        return pureNumber
    }
}

