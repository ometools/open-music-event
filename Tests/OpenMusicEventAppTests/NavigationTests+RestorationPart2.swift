import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func `an author saves an emergency comms post to the event database`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
        }

        // The author writes the announcement in the same form opened from the category.
        let store = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    draft: SocialPostDraft(
                        title: "  Gates are open  ",
                        markdown: "  **Welcome** to Wicked Woods.  "
                    )
                )
            ) {
                SocialPostForm()
            }
        }

        // Emergency delivery is available because the author owns this event.
        store.modify { $0.draft.delivery = .emergency }
        #expect(store.state.canRequestEmergency)

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }?.value
        #expect(store.isPresented == false)

        let posts = try await database.read { db in
            try Social.Post.where { $0.category.eq(categoryID) }.fetchAll(db)
        }
        let post = try #require(posts.first)
        expectNoDifference(posts.count, 1)
        expectNoDifference(post.id.authority, eventID.authority)
        expectNoDifference(post.event, eventID)
        expectNoDifference(post.category, categoryID)
        expectNoDifference(post.title, "Gates are open")
        expectNoDifference(post.text, "**Welcome** to Wicked Woods.")
        expectNoDifference(post.delivery, .known(.emergency))
    }

    @Test
    func `an author saves imported photos as a local canonical post embed`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ome-post-embed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = LocalImageFileStoreClient(
            existingFileURL: { key, _ in
                let url = directory.appending(path: key).appendingPathExtension("png")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            },
            write: { key, data, _ in
                let url = directory.appending(path: key).appendingPathExtension("png")
                try data.write(to: url, options: .atomic)
                return url
            }
        )
        let bytes = Data("Wicked Woods photo".utf8)
        let photo = ImportImages.Configuration.communicationPostPhotos.importedImage(
            title: "The gates",
            mimeType: "image/png",
            data: bytes
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.localImageFileStore = fileStore
            $0.date.now = Date(timeIntervalSince1970: 0)
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    eventID: eventID, categoryID: categoryID, author: author,
                    draft: SocialPostDraft(title: "The gates", markdown: "")
                )
            ) { SocialPostForm() }
        }
        store.modify { $0.imagePicker.append([photo]) }
        #expect(store.state.canSubmit)

        await store.send(.saveButtonTapped) { $0.isSaving = true }?.value
        #expect(store.isPresented == false)

        let post = try await database.read { db in
            try #require(try Social.Post.where { $0.category.eq(categoryID) }.fetchAll(db).first)
        }
        let embed = try #require(post.embed)
        #expect(embed.object["$type"] == "app.bsky.embed.images")
        guard case let .array(images) = try #require(embed.object["images"]) else {
            Issue.record("Expected an images embed")
            return
        }
        #expect(images.count == 1)
        guard case let .object(image) = try #require(images.first),
              case let .object(blob) = try #require(image["image"]),
              case let .object(ref) = try #require(blob["ref"]),
              case let .string(cid) = try #require(ref["$link"])
        else {
            Issue.record("Expected an image blob reference")
            return
        }
        #expect(cid.hasPrefix("bafkrei"))
        #expect(try Data(contentsOf: directory.appending(path: cid).appendingPathExtension("png")) == bytes)
    }

    @Test
    func `an author can remove one existing post photo without discarding the other`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        let firstBlob = ATProto.Blob(
            ref: "bafkreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju",
            mimeType: "image/png",
            size: 1
        )
        let secondBlob = ATProto.Blob(
            ref: "bafkreifcu6blc4yl7etxhjohn3tm2jopmz2vvxlqfgckqujm4g74adf46y",
            mimeType: "image/png",
            size: 1
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Photos", text: ""
            )
            var post = try #require(try Social.Post.find(postID).fetchOne(db))
            post.embed = Social.Post.Embed([
                "$type": "app.bsky.embed.images",
                "images": .array([
                    .object([
                        "alt": "First photo",
                        "image": try Lexicon.JSONValue(encoding: firstBlob),
                        "aspectRatio": .object(["width": 4, "height": 3]),
                    ]),
                    .object([
                        "alt": "Second photo",
                        "image": try Lexicon.JSONValue(encoding: secondBlob),
                        "aspectRatio": .object(["width": 16, "height": 9]),
                    ]),
                ]),
            ])
            try Social.Post.upsert { post }.execute(db)
        }
        let post = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        let editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    post: post, eventID: eventID, author: author
                )
            ) { SocialPostForm() }
        }
        expectNoDifference(editor.state.imagePicker.images.count, 2)
        let firstImageID = try #require(editor.state.imagePicker.images.first?.id)

        await editor.send(.imagePicker(.removeButtonTapped(firstImageID)))?.value
        expectNoDifference(editor.state.imagePicker.images.count, 1)
        await editor.send(.saveButtonTapped) { $0.isSaving = true }?.value

        let saved = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        guard case let .images(images) = SocialPostEmbedContent(try #require(saved.embed)) else {
            Issue.record("Expected one remaining photo")
            return
        }
        expectNoDifference(images.count, 1)
        expectNoDifference(images.first?.alt?.rawValue, "Second photo")
        expectNoDifference(saved.id, post.id)
        guard case let .array(savedEntries) = try #require(saved.embed?.object["images"]) else {
            Issue.record("Expected one saved image entry")
            return
        }
        expectNoDifference(
            savedEntries.first?.object?["aspectRatio"],
            .object(["width": 16, "height": 9])
        )
    }

    @Test
    func `an author can create and revise a link card on a canonical post`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
        }
        let composer = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    draft: SocialPostDraft(title: "Tickets", markdown: "")
                )
            ) { SocialPostForm() }
        }
        await composer.send(.addLinkCardButtonTapped)?.value
        composer.modify {
            $0.externalCard.uri = "https://wickedwoods.ca/tickets"
            $0.externalCard.title = "Tickets"
            $0.externalCard.summary = "Festival passes"
        }
        #expect(composer.state.canSubmit)
        await composer.send(.saveButtonTapped) { $0.isSaving = true }?.value

        var post = try await database.read { db in
            try #require(try Social.Post.where { $0.category.eq(categoryID) }.fetchAll(db).first)
        }
        guard case let .external(card) = SocialPostEmbedContent(try #require(post.embed)) else {
            Issue.record("Expected a link card")
            return
        }
        expectNoDifference(card.uri, "https://wickedwoods.ca/tickets")
        expectNoDifference(card.title, "Tickets")

        let thumbnail = ATProto.Blob(
            ref: "bafkreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju",
            mimeType: "image/png",
            size: 1
        )
        var root = try #require(post.embed).object
        var external = try #require(root["external"]?.object)
        external["thumb"] = try Lexicon.JSONValue(encoding: thumbnail)
        root["external"] = .object(external)
        root["extension"] = "keep"
        post.embed = Social.Post.Embed(root)
        let postWithThumbnail = post
        try await database.write { db in
            try Social.Post.upsert { postWithThumbnail }.execute(db)
        }

        let editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    post: post, eventID: eventID, author: author
                )
            ) { SocialPostForm() }
        }
        #expect(editor.state.hasLinkCard)
        editor.modify { $0.externalCard.summary = "Weekend and day passes" }
        await editor.send(.saveButtonTapped) { $0.isSaving = true }?.value
        let updated = try await database.read {
            try #require(try Social.Post.find(postWithThumbnail.id).fetchOne($0))
        }
        guard case let .external(updatedCard) = SocialPostEmbedContent(try #require(updated.embed)) else {
            Issue.record("Expected the revised link card")
            return
        }
        expectNoDifference(updatedCard.summary, "Weekend and day passes")
        expectNoDifference(updated.id, post.id)
        expectNoDifference(updated.embed?.object["extension"], "keep")
        expectNoDifference(updatedCard.thumbnail?.source, .known(.blob(thumbnail)))
    }

    @Test
    func `an author edits a referenced record and syndicated revisions on a canonical post`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let author = try #require(DID("did:plc:organizer"))
        let firstCID = "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        let secondCID = "bafyreifiymllu4ykepilnm6j24fstwvp72rlbiojjkpmourcjyxykm7mzu"
        let thirdCID = "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }
        let composer = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    eventID: eventID, categoryID: nil, author: author,
                    draft: SocialPostDraft(title: "Listen elsewhere", markdown: "")
                )
            ) { SocialPostForm() }
        }
        composer.send(.addRecordEmbedButtonTapped)
        composer.modify {
            $0.recordEmbed.reference.uri = "at://did:plc:artist/app.bsky.feed.post/first"
            $0.recordEmbed.reference.cid = firstCID
        }
        composer.send(.syndications(.addButtonTapped))
        composer.modify {
            $0.syndications.draft?.reference.uri = "at://did:plc:artist/app.bsky.feed.post/mirror"
            $0.syndications.draft?.reference.cid = secondCID
        }
        composer.send(.syndications(.draftSaveButtonTapped))
        #expect(composer.state.canSubmit)
        await composer.send(.saveButtonTapped) { $0.isSaving = true }?.value

        var post = try await database.read { db in
            try #require(try Social.Post.all.fetchAll(db).first)
        }
        let postID = post.id
        expectNoDifference(
            SocialPostEmbedContent(try #require(post.embed)),
            .record("at://did:plc:artist/app.bsky.feed.post/first")
        )
        expectNoDifference(post.syndications?.map(\.uri.description), [
            "at://did:plc:artist/app.bsky.feed.post/mirror"
        ])

        var object = try #require(post.embed).object
        object["extension"] = "keep"
        post.embed = Social.Post.Embed(object)
        let postWithExtension = post
        try await database.write { db in
            try Social.Post.upsert { postWithExtension }.execute(db)
        }
        let editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    post: postWithExtension, eventID: eventID, author: author
                )
            ) { SocialPostForm() }
        }
        editor.modify {
            $0.recordEmbed.reference.cid = secondCID
        }
        let originalSyndicationID = try #require(editor.state.syndications.entries.first?.id)
        editor.send(.syndications(.editButtonTapped(originalSyndicationID)))
        editor.modify { $0.syndications.draft?.reference.cid = thirdCID }
        editor.send(.syndications(.draftSaveButtonTapped))
        editor.send(.syndications(.addButtonTapped))
        editor.modify {
            $0.syndications.draft?.reference.uri = "at://did:plc:artist/app.bsky.feed.post/another"
            $0.syndications.draft?.reference.cid = firstCID
        }
        editor.send(.syndications(.draftSaveButtonTapped))
        let addedSyndicationID = try #require(editor.state.syndications.entries.last?.id)
        editor.send(.syndications(.moveButtonTapped(addedSyndicationID, -1)))
        await editor.send(.saveButtonTapped) { $0.isSaving = true }?.value

        let updated = try await database.read { db in
            try #require(try Social.Post.find(postID).fetchOne(db))
        }
        expectNoDifference(updated.id, post.id)
        expectNoDifference(updated.embed?.object["extension"], "keep")
        expectNoDifference(updated.embed?.object["record"]?.object?["cid"], .string(secondCID))
        expectNoDifference(updated.syndications?.map(\.cid.rawValue), [
            firstCID, thirdCID
        ])

        let remover = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    post: updated, eventID: eventID, author: author
                )
            ) { SocialPostForm() }
        }
        let removeID = try #require(remover.state.syndications.entries.first?.id)
        remover.send(.syndications(.deleteButtonTapped(removeID)))
        await remover.send(.saveButtonTapped) { $0.isSaving = true }?.value
        let finalPost = try await database.read { db in
            try #require(try Social.Post.find(postID).fetchOne(db))
        }
        expectNoDifference(finalPost.syndications?.map(\.cid.rawValue), [thirdCID])
    }

    @Test
    func `an author edits a canonical post without changing its identity`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let destinationCategoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcao")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalCategory(db, id: destinationCategoryID, eventID: eventID, name: "Updates")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Gates are open", text: "Welcome to the woods."
            )
        }
        let post = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }

        let editor = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 300)
            $0.defaultDatabase = database
        } operation: {
            @Dependency(\.date) var date
            #expect(date() == Date(timeIntervalSince1970: 300))
            return TestStore(
                initialState: SocialPostForm.State(
                    post: post, eventID: eventID, author: author
                )
            ) {
                SocialPostForm()
            }
        }
        editor.modify {
            $0.draft.title = "Gates are open now"
            $0.draft.delivery = .silent
            $0.categoryID = destinationCategoryID
        }
        let save = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 300)
        } operation: {
            editor.send(.saveButtonTapped) { $0.isSaving = true }
        }
        await save?.value
        #expect(editor.isPresented == false)
        let edited = try await database.read {
            try #require(try Social.Post.find(post.id).fetchOne($0))
        }
        expectNoDifference(edited.id, post.id)
        expectNoDifference(edited.createdAt, post.createdAt)
        expectNoDifference(edited.title, "Gates are open now")
        expectNoDifference(edited.category, destinationCategoryID)
        expectNoDifference(edited.delivery, .known(.silent))
        expectNoDifference(edited.updatedAt, "1970-01-01T00:05:00Z")
    }

    @Test
    func `post annotations can be created edited and deleted with UTF-8 ranges`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Links", text: "🎵 Go to example.com"
            )
        }

        let original = try #require(try await database.read { try Social.Post.find(postID).fetchOne($0) })
        let creator = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialPostForm.State(post: original, eventID: eventID, author: author)) {
                SocialPostForm()
            }
        }
        await creator.send(.addFacetButtonTapped(.link))?.value
        #expect(!creator.state.canSubmit)
        creator.modify {
            $0.facets[0].selectedText = "example.com"
            $0.facets[0].target = "https://example.com/"
        }
        await creator.send(.finishFacetButtonTapped)?.value
        #expect(creator.state.canSubmit)
        await creator.send(.saveButtonTapped) { $0.isSaving = true }?.value

        let linked = try #require(try await database.read { try Social.Post.find(postID).fetchOne($0) })
        let link = try #require(linked.facets?.first)
        #expect(link.object["index"]?.object?["byteStart"]?.integer == 11)
        #expect(link.object["index"]?.object?["byteEnd"]?.integer == 22)
        guard case let .some(.array(features)) = link.object["features"] else {
            Issue.record("Expected a link facet feature")
            return
        }
        #expect(features.first?.object?["uri"]?.string == "https://example.com/")

        let editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialPostForm.State(post: linked, eventID: eventID, author: author)) {
                SocialPostForm()
            }
        }
        let facetID = try #require(editor.state.facets.first?.id)
        await editor.send(.editFacetButtonTapped(facetID))?.value
        editor.modify {
            $0.draft.markdown = "🎵 Listen, then go to example.com"
            $0.facets[0].target = "https://example.org/"
        }
        await editor.send(.finishFacetButtonTapped)?.value
        await editor.send(.saveButtonTapped) { $0.isSaving = true }?.value

        let edited = try #require(try await database.read { try Social.Post.find(postID).fetchOne($0) })
        #expect(edited.id == original.id)
        #expect(edited.facets?.first?.object["index"]?.object?["byteStart"]?.integer == 24)
        guard case let .some(.array(editedFeatures)) = edited.facets?.first?.object["features"] else {
            Issue.record("Expected an edited link facet feature")
            return
        }
        #expect(editedFeatures.first?.object?["uri"]?.string == "https://example.org/")

        let remover = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialPostForm.State(post: edited, eventID: eventID, author: author)) {
                SocialPostForm()
            }
        }
        await remover.send(.removeFacetButtonTapped(try #require(remover.state.facets.first?.id)))?.value
        await remover.send(.saveButtonTapped) { $0.isSaving = true }?.value
        let cleared = try #require(try await database.read { try Social.Post.find(postID).fetchOne($0) })
        #expect(cleared.facets == nil)
    }

    @Test
    func `an unsupported post annotation is preserved until its text changes`() throws {
        let facet = Social.Post.Facet([
            "index": .object(["byteStart": 0, "byteEnd": 4]),
            "features": .array([.object(["$type": "example.richtext#future", "value": "x"])]),
        ])
        let entry = SocialPostFacetEntry(facet: facet, in: "Text")
        #expect(!entry.isSupported)
        #expect(entry.validationMessage(in: "Text", originalText: "Text") == nil)
        #expect(try entry.preparedFacet(in: "Text", originalText: "Text") == facet)
        #expect(entry.validationMessage(in: "Edited", originalText: "Text") != nil)
    }

    @Test
    func `mention tag and repeated-text annotations use their selected occurrences`() throws {
        var mention = SocialPostFacetEntry(kind: .mention)
        mention.selectedText = "@alice"
        mention.target = "did:plc:alice"
        let mentioned = try mention.preparedFacet(
            in: "Hi @alice", originalText: nil
        )
        guard case let .some(.array(mentionFeatures)) = mentioned.object["features"] else {
            Issue.record("Expected a mention feature")
            return
        }
        #expect(mentionFeatures.first?.object?["$type"]?.string == "app.bsky.richtext.facet#mention")
        #expect(mentionFeatures.first?.object?["did"]?.string == "did:plc:alice")

        var tag = SocialPostFacetEntry(kind: .tag)
        tag.selectedText = "#music"
        tag.target = "music"
        let tagged = try tag.preparedFacet(in: "See #music", originalText: nil)
        guard case let .some(.array(tagFeatures)) = tagged.object["features"] else {
            Issue.record("Expected a tag feature")
            return
        }
        #expect(tagFeatures.first?.object?["$type"]?.string == "app.bsky.richtext.facet#tag")
        #expect(tagFeatures.first?.object?["tag"]?.string == "music")

        var second = SocialPostFacetEntry(kind: .link)
        second.selectedText = "go"
        second.target = "https://example.com"
        second.occurrence = 1
        let repeated = try second.preparedFacet(in: "go go", originalText: nil)
        #expect(repeated.object["index"]?.object?["byteStart"]?.integer == 3)
        #expect(repeated.object["index"]?.object?["byteEnd"]?.integer == 5)
    }

    @Test
    func `editing a post preserves an unknown delivery value`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Gates are open", text: "Welcome to the woods."
            )
            var post = try #require(try Social.Post.find(postID).fetchOne(db))
            post.delivery = .unknown(.string("future-priority"))
            try Social.Post.upsert { post }.execute(db)
        }
        let futurePost = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        let futureEditor = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 600)
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SocialPostForm.State(
                    post: futurePost, eventID: eventID, author: author
                )
            ) {
                SocialPostForm()
            }
        }
        #expect(futureEditor.state.hasUnknownDelivery)
        futureEditor.modify { $0.draft.title = "" }
        await futureEditor.send(.saveButtonTapped) { $0.isSaving = true }?.value
        let cleared = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        #expect(cleared.title == nil)
        #expect(cleared.delivery == .unknown(.string("future-priority")))
    }

    @Test
    func createStageSavesNewCanonicalEventPlace() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let existingID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(
                db, id: existingID, eventID: eventID, name: "Old Meadow"
            )
        }
        let logoURL = try #require(URL(string: "https://example.com/new-logo.png"))
        let heroURL = try #require(URL(string: "https://example.com/new-hero.png"))

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EventPlaceForm.State(eventID: eventID)
            state.form.value.name = " New Meadow "
            state.category = " workshop "
            state.sortIndex = " 4 "
            state.colorHex = "#123456"
            state.iconName = OME.SemanticIcon.gridOfSquares.rawValue
            state.shortLabel = "NM"
            state.mediaEntries = [
                .init(value: .known(.image(OME.Image(
                    source: .known(.url(logoURL)),
                    role: .known(.logo)
                )))),
                .init(value: .known(.image(OME.Image(
                    source: .known(.url(heroURL)),
                    role: .known(.hero)
                )))),
            ]

            return TestStore(initialState: state) {
                EventPlaceForm()
            }
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let places = try await database.read { db in
            try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
        }
        expectNoDifference(places.count, 2)
        let stage = try #require(places.first { $0.id != existingID })
        #expect(stage.id.authority == eventID.authority)
        #expect(stage.name == "New Meadow")
        #expect(stage.stageUse?.category == "workshop")
        #expect(stage.stageUse?.sortIndex == 4)
        #expect(stage.stageUse?.color?.rawValue == 0x123456)
        #expect(stage.stageUse?.icon == .gridOfSquares)
        #expect(stage.stageUse?.shortLabel == "NM")
        let imageURLs = (stage.media ?? []).compactMap { medium -> URL? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image.displayImageAsset(recordID: eventID)?.url
        }
        expectNoDifference(
            imageURLs.map(\.absoluteString).sorted(),
            ["https://example.com/new-hero.png", "https://example.com/new-logo.png"]
        )
    }

    @Test
    func createStageAddsFirstCanonicalEventPlace() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EventPlaceForm.State(eventID: eventID)
            state.form.value.name = "Meadow Stage"
            return TestStore(initialState: state) {
                EventPlaceForm()
            }
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        let places = try await database.read { db in
            try EventPlaceList.stagesQuery(eventID: eventID).fetchAll(db)
        }
        expectNoDifference(places.map(\.name), ["Meadow Stage"])
        #expect(places.first?.id.authority == eventID.authority)
        #expect(places.first?.stageUse != nil)
    }

    @Test
    func editStageMediaImportAddsImageThroughParentDestination() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let image = ImportImages.Configuration.stagePoster.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000057a6")!,
            title: "Stage Poster",
            sourceName: "stage-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/stage-poster.png"),
            mimeType: "image/png",
            data: Data("stage-poster".utf8)
        )

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EventPlaceForm.State(eventID: eventID)) {
                EventPlaceForm()
            }
        }

        store.send(.addImageButtonTapped)
        let importStore = try #require(
            $store.scope(\.destination).importImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        var selectedImage = image
        selectedImage.image.title = image.trimmedTitle
        expectNoDifference(store.mediaEntries.map(\.importedImage), [selectedImage])
        #expect(store.mediaEntries.first?.imageValue?.image.role == .known(.poster))
    }

    @Test
    func eventPlaceListDeleteRemovesEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventPlaceList.State(eventID: eventID)) {
                EventPlaceList()
            }
        }

        await store.send(.deletePlaces([stageID]))?.value

        #expect(store.state.errorMessage == nil)

        let stage = try await database.read { db in
            try EventPlaceDetail.placeQuery(
                eventPlaceID: stageID,
                eventID: eventID
            )
            .fetchOne(db)
        }
        #expect(stage == nil)
    }

    @Test
    func launchRestoreMountsEventViewer() async throws {
        let eventID = canonicalRouteEventID
        let database = try makePreparedDatabase()
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try AppState.update {
                $0.selectedEventURI = #bind(eventID)
            }
            .execute(db)
        }

        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph },
            selectedEventIDAtLaunch: eventID
        )
        #expect(store.state.root.destination?.eventViewer?.id == eventID)
        expectNoDifference(
            store.state.root.destination?.eventViewer?.pendingScheduleLaunchAction,
            .jumpToCurrentTime
        )
    }

}
