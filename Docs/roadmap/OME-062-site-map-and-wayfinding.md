---
id: OME-062
type: roadmap-card
area: app
kind: feature
tags:
  - attendee
  - map
  - offline
  - ios
  - android
launch: wicked-woods
priority: high
created: "2026-06-11"
---

# Site Map and Wayfinding

## Summary

```gpt-5
Turn the existing site-map tab into a layered event map: a polished image/base layer where useful, hydrated by GeoJSON venue data for stages, safety points, food, muster points, camping, QR/NFC targets, and other event-specific places.
```

## Why

```gpt-5
The old planning checklist calls out Location and Site Map as separate attendee needs. The current app already has event locations, a MapKit-backed location view on supported platforms, a `siteMap` image role, a `SiteMapViewer`, and `/site-map` routing. That is the static baseline, but it is not yet the map people rely on while standing at a gate, stage, campsite, safety outpost, or info booth.

There is also prior implementation work worth recovering: the legacy `open-music-event` change `vqpwvxuytvvm` ("Site Map") introduced a `GeoSiteMapView` spike using `MKGeoJSONDecoder`, `Marker`, category filtering, and real Wicked Woods point data for entrance/check-in, stages, safety, food, muster points, camping sections, info, lost and found, ATM, wellness, and showers. The new feature should treat that as the domain proof, but move the decoding and source shape into the reusable OME model instead of leaving it as a one-off MapKit experiment.

The site map image still matters, but it should be one layer in the map, not the whole feature. A vendor-supplied festival map can be the visual base layer, while GeoJSON supplies the structured places, categories, deep-link targets, search hooks, and offline data the app can reason about.

The product target should feel closer to a rich interactive event map than to a static poster preview: attendees can pan, zoom, filter categories, tap icons, and arrive from a scan/tap point with the right place already selected. The interaction can borrow from game and festival map conventions without turning the app into a novelty interface.
```

## Rough Shape

```gpt-5
- Treat the current static map as v0 and the legacy GeoJSON spike as prior art:
  - event-level `OMERecord.ImageAsset.Role.siteMap`
  - legacy `siteMapImageURL` import support
  - `SiteMapViewer` displaying the map asset
  - `EventTarget.siteMap` and `/site-map` deep-link routing
- Model a layered map, not just a picture:
  - one or more base layers
  - raster/image base layer backed by `ImageAsset`
  - GeoJSON overlay layer backed by source repo data, blob data, or URL data
  - default viewport / camera
  - optional map bounds or control points to align a raster image with geographic coordinates
  - offline/cache policy per layer
  - attribution/source metadata
- Add a portable GeoJSON domain layer before UI dependence:
  - decode `FeatureCollection`
  - support point features first
  - preserve raw properties for forward compatibility
  - project known properties into OME concepts: `id`, `name`, `kind`, `stageID`, `placeID`, `visibility`, `priority`, `icon`, `description`, and related route target
  - validate coordinates and report diagnostics for malformed features
  - avoid making `MKGeoJSONDecoder` the source of truth; MapKit can be the iOS renderer/adapter
- First useful map categories, based on Wicked Woods data:
  - stages
  - food / market / vendors
  - safety / medical / security / ANKORS
  - muster points
  - entrance and check-in
  - information / lost and found / ATM
  - camping / accessibility / showers / wellness
- Make the map useful as an information surface:
  - category filters for dense event maps
  - selected-place cards with short descriptions and relevant actions
  - search hooks for place names, categories, and stage names
  - clear icons and colors that match the event theme without sacrificing legibility
  - lightweight motion such as zooming to a selected place only when it helps orientation
- Polish the image/base layer as part of the map:
  - pinch/drag/zoom behavior that feels natural on iOS and Android
  - initial fit-to-screen framing
  - quick reset-to-fit control
  - loading, failed-load, and missing-map states
  - readable full-screen presentation from the Site Map tab and QR/NFC entry
  - cache/offline behavior aligned with `OpenMusicEventImages`
  - no required location permission just to read the map
- Connect the map to the rest of the event surface:
  - deep links and QR routes open the site map directly
  - place-level deep links can select and zoom to one map feature
  - stage detail can link to the map when a stage has map context
  - selected stage map features can link back to the stage schedule/detail
  - location view can link to site map when the raster map is more useful than external Apple/Google Maps
  - contact/safety info remains reachable from the map surface
- Connect the map to App Clip / NFC onboarding:
  - an NFC/QR target can open a place-specific map view
  - the entry can zoom to the selected place and show a compact info sheet
  - physical NFC devices can stay generic while source data associates each installed object with a map place and route target
  - stage entrances and installations are first-class examples, not edge cases
- Keep venue maps separate from broad event discovery:
  - event `locations` continue to model venue address, directions, coordinates, and external map links
  - nearby / location-permission features remain optional overlays, not prerequisites
  - AppView nearby-event search remains in [[OME-059-community-calendar-appview-ingestion|Community Calendar AppView Ingestion]]
- Possible source shape:
  - `events/<event>/maps/main.yml` for map metadata, layer order, default viewport, and cache policy
  - `events/<event>/maps/places.geojson` for venue features
  - existing event image assets for raster base layers
  - source-backed editing and validation before organizers rely on it
- Dependencies / adjacent cards: [[OME-011-stages-location-posters-and-event-info|Stages, Location, Posters, and Event Info]], [[OME-019-image-import-and-local-image-storage|Image Import and Local Image Storage]], [[OME-030-attendee-facing-polish|Attendee-Facing Polish]], [[OME-055-universal-links-and-deep-link-routing|Universal Links and Deep-Link Routing]], [[OME-056-app-clip-and-android-instant-app-entry|App Clip and Android Instant App Entry]], [[OME-057-on-site-qr-onboarding-system|On-Site QR Onboarding System]], [[OME-060-in-app-onboarding-and-permission-tour|In-App Onboarding and Permission Tour]].
- Code pointers: `Sources/OpenMusicEventAppEventViewer/SiteMapViewer.swift`, `Sources/OpenMusicEventAppEventViewer/LocationViewer.swift`, `Sources/OpenMusicEventAppEventViewer/EventViewer.swift`, `Sources/OpenMusicEventAppEventViewer/EventNavigation.swift`, `Sources/OpenMusicEventApp/OpenMusicEventRoute.swift`, `Sources/OpenMusicEventLexicon/ImageAsset.swift`, `Sources/OpenMusicEventSource/DTOs.swift`, `Sources/OpenMusicEventSource/FileTrees.swift`, `Sources/OpenMusicEventImages`, and legacy `open-music-event` change `vqpwvxuytvvm`.
```

## Product Shape

```gpt-5
The useful/showy version should be organized around real attendee modes, not around map technology:

- Browse: open Site Map from the event tab and scan the whole grounds.
- Find: filter or search for stages, food, safety, info, camping, bathrooms/showers, and accessibility.
- Arrive: scan/tap a QR/NFC point and land on the map with the relevant place selected.
- Act: jump from a selected map place to schedule, stage detail, contact/safety, or event support.

The first "showy" moment should be practical: a QR/NFC scan at a stage entrance or installation opens the map already framed on that place, with a compact sheet that names where the attendee is and what they can do next. That is a stronger demo than decorative animation because it proves the app understands the physical event.

The map should never require location permission for core use. User location can become a later overlay, but the launch feature should work from event source data, cached assets, and deep links.
```

## Architecture Sketch

```gpt-5
The feature wants four boundaries:

1. Source/import boundary
   - `maps/main.yml` declares map metadata, layer order, default viewport, georeferencing, and cache policy.
   - `maps/places.geojson` carries structured event places.
   - Existing image assets remain the source of raster base layers through `ImageAsset.Role.siteMap`.
   - Source validation should fail loudly enough for organizers before the event, but degrade clearly in the attendee app.

2. Portable map domain boundary
   - Decode a GeoJSON subset without MapKit.
   - Preserve raw properties.
   - Project known properties into OME map places.
   - Produce diagnostics for malformed geometry, missing IDs, unknown place kinds, invalid coordinates, duplicate IDs, broken stage links, and broken route targets.
   - Keep coordinate parsing and category semantics testable without rendering.

3. Persistence/projection boundary
   - Add event-map/map-place records or an equivalent queryable projection, instead of hiding the whole feature inside `EventDTO`.
   - Link map places to stages, event targets, source file provenance, image layers, and QR/NFC placements.
   - Keep map-place IDs stable across source imports so deep links and physical signage do not break.

4. Renderer boundary
   - iOS can use MapKit as an adapter for geographic rendering.
   - Android needs an explicit renderer decision: native maps, MapLibre, or an image/canvas overlay fallback.
   - The existing image-only `SiteMapViewer` remains the fallback when structured data is absent or invalid.
   - Rendering should consume OME map-domain values, not raw GeoJSON or MapKit-only types.
```

## Community Location Lexicon Fit

```gpt-5
Current protocol/community evidence points to a useful but limited fit:

- Official Bluesky `app.bsky.feed.post` has no location field, and the current official `site.standard` lexicons do not define a place/location primitive for this use case.
- Smoke Signal, an active ATProto event app hosted on Tangled, supports `community.lexicon.calendar.event`, `community.lexicon.calendar.rsvp`, and `community.lexicon.location`.
- Smoke Signal's current `atproto-record` types model `community.lexicon.location` as `LocationOrRef`: a strong reference or one inline value from:
  - `community.lexicon.location.address`
  - `community.lexicon.location.geo`
  - `community.lexicon.location.hthree`
  - `community.lexicon.location.fsq`
- The address shape has required `country`, plus optional `postalCode`, `region`, `locality`, `street`, and `name`.
- The geo shape has `latitude`, `longitude`, and optional `name`; coordinates are strings in the Rust type to preserve precision.
- The H3 shape has `value` and optional `name`.
- The Foursquare shape has `fsq_place_id` and optional `name`.
- `community.lexicon.calendar.event` has `locations: Locations`, event `media`, event `uris`, status, mode, and rich-text facets.

That means OME should align with community location for event-level venue identity and nearby-event discovery, but should not force the whole site-map domain into `community.lexicon.location`.

The fit should be:

- Event venue/address:
  - map OME event `locations` to community `address`, `geo`, or `hthree` where possible.
  - this is the right level for AppView nearby search and public calendar interoperability.
- Festival site-map places:
  - keep as OME map-place records/source data.
  - optionally include a `communityLocation` projection for places that are safe and useful to expose as generic locations.
  - do not publish every campsite label, safety outpost, or operational point as an event-level community calendar location.
- Raster/image map:
  - can be exposed as event media with a `siteMap`/map-like role if an ATProto sync surface wants it.
  - layer ordering, georeference, opacity, and source diagnostics remain OME-specific.
- QR/NFC physical points:
  - can reference a community location projection if one exists.
  - still need OME-specific route targets, installation metadata, source IDs, and event-scoped behavior.

The practical modeling rule: community lexicons describe "where this event/place is in the world"; OME map data describes "how this event works on the ground."
```

## Lexicon Evidence

```gpt-5
Checked on 2026-06-11:

- Smoke Signal app repo on Tangled: `https://tangled.org/smokesignal.events/smokesignal`
  - README lists support for `community.lexicon.calendar.event`, `community.lexicon.calendar.rsvp`, and `community.lexicon.location`.
  - `Cargo.toml` depends on `atproto-record` from `https://tangled.org/@smokesignal.events/atproto-identity-rs`.
  - `events.smokesignal.lfg` references `community.lexicon.location#geo` for geographic matching.
  - Search indexing extracts inline `community.lexicon.location.geo` into lat/lon points and computes location CIDs from `LocationOrRef`.
- Smoke Signal `atproto-record` dependency on Tangled: `https://tangled.org/smokesignal.events/atproto-identity-rs`
  - `community_lexicon_location.rs` defines the current Rust shape for `address`, `geo`, `hthree`, `fsq`, and `LocationOrRef`.
  - `community_lexicon_calendar_event.rs` defines `community.lexicon.calendar.event` with `locations: Locations`, `uris`, `media`, status, mode, and facets.
- Official ATProto repo checked for contrast:
  - `app.bsky.feed.post` currently has text/facets/reply/embed/langs/labels/tags/createdAt, not a location field.
  - `site.standard.document` uses open unions for content/links, but does not establish the event-place/map-layer shape OME needs.

Because many Atmosphere apps and lexicons are protocol-native or hosted on Tangled, GitHub/Google search should be treated as incomplete. Future research should start from known repos, NSIDs, service READMEs, and protocol records where possible.
```

## Source Shape Sketch

```gpt-5
Start with a source shape that can be edited by humans and generated by tooling:

    # events/<event>/maps/main.yml
    id: main
    title: Site Map
    defaultViewport:
      center:
        latitude: "50.3637"
        longitude: "-115.8769"
      span:
        latitudeDelta: "0.015"
        longitudeDelta: "0.015"
    layers:
      - id: festival-map
        kind: imageBase
        imageRole: siteMap
        opacity: 1
        georeference:
          kind: bounds
          northWest:
            latitude: "50.3710"
            longitude: "-115.8860"
          southEast:
            latitude: "50.3550"
            longitude: "-115.8670"
      - id: places
        kind: geoJSON
        path: places.geojson
        visibleByDefault: true
    offline:
      cache: required
      failureMode: showLastKnownOrImageOnly

    {
      "type": "Feature",
      "id": "ursus-stage",
      "geometry": { "type": "Point", "coordinates": [-115.8769, 50.3637] },
      "properties": {
        "name": "Ursus",
        "kind": "stage",
        "stageID": "ursus",
        "visibility": "public",
        "priority": 100,
        "icon": "stage",
        "route": "/stages/ursus",
        "communityLocation": {
          "$type": "community.lexicon.location.geo",
          "latitude": "50.3637",
          "longitude": "-115.8769",
          "name": "Ursus"
        }
      }
    }

The embedded `communityLocation` should be optional and treated as an interoperability projection, not the source of truth for OME-specific map behavior.
```

## Swift/API Sketch

```gpt-5
The first implementation slice should keep these as plain domain/source types before tying them to SQLite or SwiftUI:

    struct EventMapDTO: Codable, Equatable, Sendable {
      var id: String
      var title: String?
      var defaultViewport: MapViewportDTO?
      var layers: [MapLayerDTO]
      var offline: MapOfflinePolicyDTO?
    }

    struct MapLayerDTO: Codable, Equatable, Sendable, Identifiable {
      enum Kind: String, Codable, Sendable {
        case imageBase
        case geoJSON
      }

      var id: String
      var kind: Kind
      var imageRole: ImageAsset.Role?
      var path: String?
      var opacity: Double?
      var visibleByDefault: Bool?
      var georeference: MapGeoreferenceDTO?
    }

    struct EventMapPlace: Equatable, Identifiable, Sendable {
      var id: String
      var name: String
      var kind: EventMapPlaceKind
      var coordinate: GeoCoordinate
      var stageID: OMERecord.Stage.ID?
      var route: EventTarget?
      var visibility: EventMapPlaceVisibility
      var priority: Int?
      var communityLocation: CommunityLocationProjection?
      var rawProperties: [String: JSONValue]
    }

    enum CommunityLocationProjection: Equatable, Sendable {
      case address(CommunityAddressLocation)
      case geo(CommunityGeoLocation)
      case hthree(CommunityH3Location)
      case fsq(CommunityFoursquareLocation)
    }

`EventMapPlaceKind` should probably be open enough to keep unknown organizer categories as data while still giving the app first-class cases for `stage`, `food`, `safety`, `medical`, `security`, `muster`, `entrance`, `info`, `camping`, `accessibility`, `showers`, `wellness`, `vendor`, and `installation`.
```

## Implementation Slices

```gpt-5
1. Recover and repair the legacy fixture
   - Extract the Wicked Woods point data from legacy change `vqpwvxuytvvm`.
   - Repair malformed inline JSON into valid GeoJSON.
   - Save it as a source-style fixture with `maps/main.yml` and `maps/places.geojson`.
   - Include a small community-location sample in one or two public places.
   - Test that the fixture decodes without MapKit.

2. Build the portable parser/diagnostics layer
   - Decode GeoJSON FeatureCollection and point features.
   - Preserve raw properties.
   - Project known properties into `EventMapPlace`.
   - Validate coordinates, IDs, categories, stage links, route targets, visibility, and community-location projections.
   - Use CustomDump-style assertions for diagnostics once tests are written.

3. Add source-file integration
   - Extend `OpenMusicEventSource` file trees with optional `maps/`.
   - Parse `maps/main.yml` and `maps/*.geojson`.
   - Keep maps optional so existing event sources continue to import.
   - Surface source provenance in diagnostics so a bad feature points back to the file and feature ID.

4. Add persistence/query shape
   - Decide whether map data becomes normalized records, a map projection table, or event-scoped embedded JSON with query helpers.
   - Make selected place lookup fast by stable ID for QR/NFC and deep links.
   - Keep event-level `locations` separate from site-map places.

5. Polish image-only Site Map v1
   - Improve the current image viewer with fit-to-screen, pinch/drag/zoom, reset, loading, failure, and offline states.
   - Add route round-trip tests for `/site-map` if still missing.
   - This gives immediate attendee value before the full overlay renderer lands.

6. Add iOS structured map rendering
   - Render base image where available and structured points from `EventMapPlace`.
   - Add category filters, selected-place cards, and stage/detail links.
   - Keep location permission out of the first version.
   - Treat MapKit as an adapter, not the parser.

7. Add place-level routes and QR/NFC entry
   - Support `/site-map/places/<place-id>` or an equivalent event route.
   - Open the map with a selected place and camera request.
   - Connect reusable physical info-point IDs from OME-057 to map places and route targets.

8. Decide and prove Android behavior
   - Recover the legacy Telephoto image zoom path for image-only parity if still useful.
   - Spike MapLibre/native map vs image+overlay for structured points.
   - Define Android launch readiness before calling the feature complete.

9. Add visual polish after the data path is real
   - Event-themed icon set and category colors.
   - Animated camera movement only for selection/deep-link orientation.
   - Full-screen map presentation that keeps schedule, contact, and safety reachable.
   - Snapshot/manual screenshot checks for small phone, large phone, and Android.
```

## Open Questions

```gpt-5
- Should raster site-map images be geo-referenced with bounds/control points, or should they remain visual-only layers that sit beside a native geographic map?
- Should map metadata live in `maps/main.yml`, directly on the event record, or in a more general event-place/source model shared with QR/NFC placements?
- What is the minimal property contract for GeoJSON features: `id`, `name`, `kind`, `stageID`, `route`, and `visibility`, or something richer from the start?
- Should the first renderer be MapKit-only behind an OME parser, or should the first slice prove iOS and Android renderers together?
- How much of the legacy Wicked Woods point data is still accurate enough to use as a fixture?
- How should safety, medical, and muster points be handled in public app data versus staff-only/event-ops data?
- Which interaction conventions matter for launch: category filters, search, selected-place cards, custom iconography, animated zoom, or just excellent pan/zoom performance?
- Does App Clip / NFC entry start with the map selected and zoomed to a place, or with a compact place detail that can open the full map?
- Should OME define an ATProto lexicon for event map places, or keep the first version as source-repo GeoJSON with optional `community.lexicon.location` projections?
- Which site-map places are safe/useful to expose as community locations, and which should remain event-private or OME-only?
- Should H3 cells be generated for event-level nearby search only, or also for coarse onsite areas such as camp sections?
```

## Acceptance Checks

```gpt-5
- The recovered Wicked Woods GeoJSON data can be repaired into valid fixture data and decoded by an OME-owned parser without MapKit.
- The parser can recognize optional `community.lexicon.location.geo`, `address`, `hthree`, and `fsq` projections without treating them as the OME map-place source of truth.
- A source repository can include map metadata plus a GeoJSON layer, and parser tests prove it imports into the local database/projection shape.
- The Site Map tab can render a base image layer and structured place overlay, or gracefully render only the available layer.
- Category filtering can show at least stages, food, safety, and muster points from one real event fixture.
- `/site-map` routes round-trip through `AppRoute` tests and select the Site Map feature.
- Place-level QR/NFC/deep links can open the map with one feature selected, or fall back to the full site map when the place is unavailable.
- Missing, loading, failed-load, malformed-GeoJSON, and offline states are explicit and do not look like an empty event.
- The image/base layer remains usable on small phones and does not trap the attendee away from schedule, location, contact, or safety surfaces.
- Android behavior is intentionally defined before the feature is treated as launch-ready.
```

## Next Step

```gpt-5
Recover the legacy `vqpwvxuytvvm` Site Map spike into a small fixture: extract and repair the Wicked Woods point GeoJSON, add `maps/main.yml` plus `maps/places.geojson`, include one or two optional `community.lexicon.location` projections, and add parser/diagnostic tests before building the new layered `SiteMapViewer` UI.
```
