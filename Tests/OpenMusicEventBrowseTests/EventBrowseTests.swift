import ATProto
import ComposableArchitecture2
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventLexicon
import Testing
@testable import OpenMusicEventApp

@MainActor
struct EventBrowseTests {
    @Test
    func `artist search keeps server matches and loads the next page without duplicates`() async throws {
        let first = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/2026",
            catalog: "events.openmusic.event", name: "Wicked Woods 2026", hasEventViewer: true)
        let second = OME.CalendarEvent.Summary(uri: "at://did:plc:venue/community.lexicon.calendar.event/dance",
            catalog: "community.lexicon.calendar.event", name: "Community Dance")
        let evaluatedAt = Date(timeIntervalSince1970: 100)
        let publishers = EventBrowseClient.PublisherSelection(mode: "allExcept", publishers: [7])
        let requests = LockIsolated<[OME.CalendarEvent.BrowseSummaries.Parameters]>([])
        let store = withDependencies {
            $0.continuousClock = .immediate
            $0.eventBrowse.defaults = { publishers }
            $0.eventBrowse.browse = { request in
                requests.withValue { $0.append(request) }
                return request.cursor == nil
                    ? .init(events: [first], cursor: "page-two", hasMore: true, evaluatedAt: evaluatedAt)
                    : .init(events: [first, second], evaluatedAt: evaluatedAt)
            }
        } operation: {
            TestStore(initialState: Browse.State()) { Browse() }
        }

        // An artist query searches both catalogs, including matches outside the event title.
        await store.send(.searchTextChanged("Woofax")) {
            $0.searchText = "Woofax"
            $0.requestGeneration = 1
            $0.isLoading = true
        }?.value
        store.expect {
            $0.events = [first]
            $0.cursor = "page-two"
            $0.evaluatedAt = evaluatedAt
            $0.publisherSelection = publishers
            $0.isLoading = false
            $0.hasLoaded = true
        }
        expectNoDifference(requests.value, [.init(
            catalogs: EventCatalog.allCases.map(\.collection), query: "Woofax", limit: 50,
            dates: "current", publisherMode: "allExcept", publishers: [7]
        )])

        // The next page follows the opaque cursor and keeps the server's order.
        await store.send(.loadMoreButtonTapped) { $0.isLoadingMore = true }?.value
        store.expect {
            $0.events = [first, second]
            $0.cursor = nil
            $0.isLoadingMore = false
        }
        #expect(requests.value.last?.cursor == "page-two")
        await store.send(.loadMoreButtonTapped)?.value
        #expect(requests.value.count == 2)
        await store.dismount()
    }

    @Test
    func `repeated search text from the search field does not cancel the pending request`() async throws {
        let clock = TestClock()
        let event = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/2026",
            catalog: "events.openmusic.event", name: "Wicked Woods 2026")
        let now = Date(timeIntervalSince1970: 100)
        let selection = EventBrowseClient.PublisherSelection(mode: "allExcept", publishers: [])
        let requests = LockIsolated(0)
        let store = withDependencies {
            $0.continuousClock = clock
            $0.eventBrowse.defaults = { selection }
            $0.eventBrowse.browse = { _ in
                requests.withValue { $0 += 1 }
                return .init(events: [event], evaluatedAt: now)
            }
        } operation: { TestStore(initialState: Browse.State()) { Browse() } }

        let request = store.send(.searchTextChanged("Woofax")) {
            $0.searchText = "Woofax"; $0.requestGeneration = 1; $0.isLoading = true
        }
        // SwiftUI may write the same text again while ending editing.
        store.send(.searchTextChanged("Woofax"))
        await clock.advance(by: .milliseconds(300))
        await request?.value
        store.expect {
            $0.events = [event]; $0.evaluatedAt = now; $0.publisherSelection = selection
            $0.isLoading = false; $0.hasLoaded = true
        }
        #expect(requests.value == 1)
        await store.dismount()
    }

    @Test
    func `a failed next page can be retried and changing catalogs starts a new search`() async throws {
        let event = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/2026",
            catalog: "events.openmusic.event", name: "Wicked Woods 2026")
        let now = Date(timeIntervalSince1970: 100)
        let selection = EventBrowseClient.PublisherSelection(mode: "allExcept", publishers: [])
        let attempts = LockIsolated(0)
        let requests = LockIsolated<[OME.CalendarEvent.BrowseSummaries.Parameters]>([])
        let store = withDependencies {
            $0.eventBrowse.defaults = { selection }
            $0.eventBrowse.browse = { request in
                requests.withValue { $0.append(request) }
                if request.cursor != nil {
                    let attempt = attempts.withValue { $0 += 1; return $0 }
                    if attempt == 1 { throw URLError(.notConnectedToInternet) }
                    return .init(events: [], evaluatedAt: now)
                }
                return .init(events: [event], cursor: "next", hasMore: true, evaluatedAt: now)
            }
        } operation: { TestStore(initialState: Browse.State()) { Browse() } }

        await store.send(.task) { $0.requestGeneration = 1; $0.isLoading = true }?.value
        store.expect {
            $0.events = [event]; $0.cursor = "next"; $0.evaluatedAt = now
            $0.publisherSelection = selection; $0.isLoading = false; $0.hasLoaded = true
        }
        // A transient failure keeps the visible events and the cursor needed to retry.
        await store.send(.loadMoreButtonTapped) { $0.isLoadingMore = true }?.value
        store.expect { $0.isLoadingMore = false; $0.moreError = "Unable to load more events. Try again." }
        await store.send(.loadMoreButtonTapped) { $0.isLoadingMore = true; $0.moreError = nil }?.value
        store.expect { $0.isLoadingMore = false; $0.cursor = nil }

        // Each filter change starts at page one; neither catalog is an implicit fallback.
        await store.send(.catalogToggled(.openMusicEvent)) {
            $0.catalogs = [.communityCalendar]; $0.events = []; $0.evaluatedAt = nil
            $0.requestGeneration = 2; $0.isLoading = true; $0.hasLoaded = false
        }?.value
        store.expect {
            $0.events = [event]; $0.cursor = "next"; $0.evaluatedAt = now
            $0.isLoading = false; $0.hasLoaded = true
        }
        #expect(requests.value.last?.catalogs == [EventCatalog.communityCalendar.collection])
        #expect(requests.value.last?.cursor == nil)
        await store.send(.dateScopeSelected(.all)) {
            $0.dateScope = .all; $0.events = []; $0.cursor = nil; $0.evaluatedAt = nil
            $0.requestGeneration = 3; $0.isLoading = true; $0.hasLoaded = false
        }?.value
        store.expect {
            $0.events = [event]; $0.cursor = "next"; $0.evaluatedAt = now
            $0.isLoading = false; $0.hasLoaded = true
        }
        #expect(requests.value.last?.dates == "all")
        #expect(requests.value.last?.cursor == nil)
        await store.send(.catalogToggled(.communityCalendar)) {
            $0.catalogs = []; $0.events = []; $0.cursor = nil; $0.evaluatedAt = nil
            $0.requestGeneration = 4; $0.hasLoaded = false
        }?.value
        #expect(requests.value.count == 5)
        await store.dismount()
    }

    @Test
    func `a late search response cannot replace a newer query`() async throws {
        let stale = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/old",
            catalog: "events.openmusic.event", name: "Old result")
        let current = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/new",
            catalog: "events.openmusic.event", name: "New result")
        let now = Date(timeIntervalSince1970: 100)
        let selection = EventBrowseClient.PublisherSelection(mode: "allExcept", publishers: [])
        let started = AsyncStream<Void>.makeStream()
        let response = AsyncStream<OME.CalendarEvent.SummaryPage>.makeStream()
        defer { started.continuation.finish(); response.continuation.finish() }
        let store = withDependencies {
            $0.continuousClock = .immediate
            $0.eventBrowse.defaults = { selection }
            $0.eventBrowse.browse = { request in
                if request.query == "old" {
                    started.continuation.yield(())
                    for await page in response.stream { return page }
                    throw CancellationError()
                }
                return .init(events: [current], evaluatedAt: now)
            }
        } operation: { TestStore(initialState: Browse.State()) { Browse() } }

        let oldRequest = store.send(.searchTextChanged("old")) {
            $0.searchText = "old"; $0.requestGeneration = 1; $0.isLoading = true
        }
        // Wait for the actual suspended request, without assuming task scheduling.
        var starts = started.stream.makeAsyncIterator()
        _ = await starts.next()
        await store.send(.searchTextChanged("new")) {
            $0.searchText = "new"; $0.requestGeneration = 2
        }?.value
        store.expect {
            $0.events = [current]; $0.evaluatedAt = now; $0.publisherSelection = selection
            $0.isLoading = false; $0.hasLoaded = true
        }
        response.continuation.yield(.init(events: [stale], cursor: "stale-cursor", hasMore: true, evaluatedAt: now))
        await oldRequest?.value
        expectNoDifference(store.events, [current])
        #expect(store.cursor == nil)
        await store.dismount()
    }

    @Test
    func `browse sends the web contract anonymously to the selected AppView`() async throws {
        let requests = LockIsolated<[String]>([])
        let event = OME.CalendarEvent.Summary(uri: "at://did:plc:festival/events.openmusic.event/2026",
            catalog: "events.openmusic.event", name: "Wicked Woods 2026", dateOnly: true, hasEventViewer: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let page = try encoder.encode(OME.CalendarEvent.SummaryPage(events: [event], evaluatedAt: Date(timeIntervalSince1970: 100)))
        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = { request, body in
                let url = try #require(request.url)
                #expect(url.host == "stg.openmusicevent.app")
                #expect(request.headerFields[.authorization] == nil)
                #expect(body == nil)
                requests.withValue { $0.append(url.path) }
                if url.path.hasSuffix("getPublishers") {
                    return (Data(#"{"defaults":{"mode":"allExcept","publishers":[7]},"publishers":[],"cursor":null}"#.utf8), HTTPResponse(status: .ok))
                }
                let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                expectNoDifference(items.filter { $0.name == "catalogs" }.compactMap(\.value).sorted(),
                    EventCatalog.allCases.map { $0.collection.rawValue }.sorted())
                #expect(items.contains(URLQueryItem(name: "query", value: "Woofax")))
                #expect(items.contains(URLQueryItem(name: "cursor", value: "opaque+cursor=")))
                #expect(items.contains(URLQueryItem(name: "dates", value: "all")))
                #expect(items.contains(URLQueryItem(name: "publisherMode", value: "allExcept")))
                #expect(items.contains(URLQueryItem(name: "publishers", value: "7")))
                #expect(items.contains(URLQueryItem(name: "limit", value: "50")))
                return (page, HTTPResponse(status: .ok))
            }
        } operation: {
            let client = EventBrowseClient.appView(host: "stg.openmusicevent.app")
            let defaults = try await client.defaults()
            let page = try await client.browse(.init(catalogs: EventCatalog.allCases.map(\.collection),
                query: "Woofax", cursor: "opaque+cursor=", limit: 50, dates: "all",
                publisherMode: defaults.mode, publishers: defaults.publishers))
            expectNoDifference(page.events, [event])
            let preview = try event.browsePreview()
            #expect(preview.uri.description == event.uri)
        }
        expectNoDifference(requests.value, ["/xrpc/app.openmusicevent.calendar.getPublishers",
            "/xrpc/app.openmusicevent.calendar.browseEventSummaries"])
    }

    @Test
    func `community details keep their record address and use the selected AppView`() async throws {
        let uri = try #require(ATProto.URI("at://did:plc:venue/community.lexicon.calendar.event/dance"))
        let link = try #require(URL(string: "https://venue.example/tickets"))
        let event = OME.CalendarEvent(uri: uri, name: "Community Dance", description: "Live music",
            startsAt: Date(timeIntervalSince1970: 100), locations: [.init(name: "The Hall")],
            links: [.init(name: "Tickets", uri: link)],
            organizer: .init(id: try #require(DID("did:plc:venue")), displayName: "The Venue"),
            source: .init(collection: "community.lexicon.calendar.event"), timeZoneIdentifier: "America/Denver")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = { request, _ in
                let url = try #require(request.url)
                #expect(url.host == "stg.openmusicevent.app")
                #expect(url.path == "/xrpc/app.openmusicevent.calendar.getEvent")
                #expect(request.headerFields[.authorization] == nil)
                let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                #expect(items.contains(URLQueryItem(name: "uri", value: uri.description)))
                return (data, HTTPResponse(status: .ok))
            }
        } operation: {
            let detail = try await EventBrowseClient.appView(host: "stg.openmusicevent.app").event(uri)
            #expect(detail.uri == uri)
            #expect(detail.description == "Live music")
            #expect(detail.locations.first?.summary == "The Hall")
            #expect(detail.links.first?.uri == link)
            #expect(detail.timeZoneIdentifier == "America/Denver")
            #expect(detail.source.appViewHost == "stg.openmusicevent.app")
        }
    }

}
