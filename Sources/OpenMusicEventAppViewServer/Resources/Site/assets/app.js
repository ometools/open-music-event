const DEFAULT_CONFIG = {
  xrpcURL: "/xrpc/app.openmusicevent.calendar.browseEventSummaries",
  mapItemsURL: "/xrpc/app.openmusicevent.calendar.getSearchMapItems",
  eventURL: "/xrpc/app.openmusicevent.calendar.getEvent",
  catalogs: ["events.openmusic.event", "community.lexicon.calendar.event"],
  mapStyle: "https://tiles.openfreemap.org/styles/liberty",
  initialCenter: [-104.5, 39.5],
  initialZoom: 2.05,
};

const config = { ...DEFAULT_CONFIG, ...(window.OME_CALENDAR_CONFIG || {}) };
const params = new URLSearchParams(window.location.search);
if (params.has("xrpc")) config.xrpcURL = params.get("xrpc");
if (params.has("style")) config.mapStyle = params.get("style");

const palette = ["#a05cff", "#42d8ff", "#f354ca", "#6279ff", "#21d7b5", "#df61ff"];
const state = {
  listEvents: [],
  mapPoints: [],
  mapClusters: [],
  searchClusterMembers: {},
  highlightedMembers: null,
  clusterBrowseBounds: null,
  selectedID: null,
  selectedDetails: null,
  detailCache: new Map(),
  detailController: null,
  query: "",
  dates: "current",
  searchBounds: null,
  clusterCell: null,
  pageCursors: [],
  currentCursor: null,
  tileFilterKey: null,
  fitSearch: false,
  bounds: null,
  cursor: null,
  map: null,
  mapReady: false,
  imageMarkers: new Map(),
  pendingMapReadyAt: null,
  mapItemMetrics: null,
  skipNextMoveReload: false,
  userLocation: null,
  selectedCatalogs: new Set(config.catalogs),
  requestController: null,
  clusterRequestController: null,
  mapRequestController: null,
  requestID: 0,
  mapRequestID: 0,
  reloadTimer: null,
  mapReloadTimer: null,
  hasMore: false,
  displayStartedAt: performance.now(),
  displayedRequestID: 0,
  tileTimings: [],
  firstVisibleMarkersMilliseconds: null,
};

const ids = [
  "dataStatus", "listHeading", "jumpToNow", "loadMore", "previousPage", "dateMode", "searchArea", "searchEverywhere", "showPageResults",
  "eventList", "resultCount", "emptyState", "resetFilters", "mapCard", "mapFallback",
  "searchForm", "searchInput", "locateButton", "resetMapButton", "zoomInButton",
  "zoomOutButton", "eventCardTemplate", "selectionConnector", "connectorPath",
];
const els = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));

function hashString(value) {
  let hash = 2166136261;
  for (const char of value) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function normalizeEvent(raw) {
  if (typeof raw.uri !== "string" || raw.uri.length === 0) return null;
  const collection = raw.catalog || raw.source?.collection
    || (raw.uri.includes("/events.openmusic.event/")
      ? "events.openmusic.event"
      : "community.lexicon.calendar.event");
  const source = collection === "events.openmusic.event"
    ? "openMusicEvent"
    : "communityCalendar";
  const dateOnly = raw.dateOnly === true || (source === "openMusicEvent"
    && /^\d{4}-\d{2}-\d{2}$/.test(raw.event?.startDate || ""));
  const start = raw.startsAt
    ? new Date(raw.startsAt)
    : null;
  const end = raw.endsAt ? new Date(raw.endsAt) : null;
  const locations = Array.isArray(raw.locations) ? raw.locations : [];
  const mappedLocation = locations.find(location => (
    Number.isFinite(Number(location.latitude)) && Number.isFinite(Number(location.longitude))
  ));
  const location = mappedLocation || locations[0] || {};
  const latitude = raw.latitude ?? location.latitude;
  const longitude = raw.longitude ?? location.longitude;
  const coordinates = latitude != null && longitude != null && Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude))
    ? [Number(longitude), Number(latitude)]
    : null;
  const media = preferredMedia(raw.media);
  const markerMedia = raw.markerMedia || preferredMarkerMedia(raw.media)
    || (typeof raw.organizer?.avatarURL === "string"
      ? { url: raw.organizer.avatarURL, role: "avatar", renderKind: "fullImage" }
      : null);
  const seed = hashString(raw.uri);
  return {
    ...raw,
    name: raw.name || "Untitled event",
    source,
    dateOnly,
    date: start && !Number.isNaN(start.valueOf()) ? start : null,
    endDate: end && !Number.isNaN(end.valueOf()) ? end : null,
    timezone: raw.timeZoneIdentifier || null,
    locationSummary: raw.locationSummary || location.name
      || [location.street, location.locality, location.region, location.postalCode, location.country]
        .filter(Boolean).join(", ")
      || (coordinates ? "Open for location details" : "Location to be announced"),
    locality: location.locality || null,
    region: location.region || null,
    country: location.country || null,
    coordinates,
    color: palette[seed % palette.length],
    image: media?.url || markerMedia?.url || null,
    imageRole: media?.role || null,
    imageRenderKind: media?.renderKind || markerMedia?.renderKind || null,
    markerImage: markerMedia?.url || null,
    markerImageRole: markerMedia?.role || null,
    markerImageRenderKind: markerMedia?.renderKind || null,
    quality: coordinates ? [] : ["missingCoordinates"],
  };
}

function normalizeCluster(raw) {
  const values = [
    raw.latitude,
    raw.longitude,
    raw.north,
    raw.south,
    raw.east,
    raw.west,
    raw.expansionZoom,
  ].map(Number);
  if (
    typeof raw.id !== "string"
    || !Number.isInteger(raw.count)
    || raw.count < 2
    || values.some(value => !Number.isFinite(value))
  ) return null;
  return {
    ...raw,
    coordinates: [values[1], values[0]],
    bounds: {
      north: values[2],
      south: values[3],
      east: values[4],
      west: values[5],
    },
    expansionZoom: values[6],
  };
}

function preferredMedia(media) {
  if (!Array.isArray(media)) return null;
  const rolePriority = ["icon", "poster", "hero", "photo", "logo", "avatar"];
  return [...media].sort((a, b) => {
    const aPriority = rolePriority.indexOf(a.role);
    const bPriority = rolePriority.indexOf(b.role);
    return (aPriority < 0 ? rolePriority.length : aPriority)
      - (bPriority < 0 ? rolePriority.length : bPriority);
  }).find(item => typeof item.url === "string" && item.url.length > 0) || null;
}

function preferredMarkerMedia(media) {
  if (!Array.isArray(media)) return null;
  const rolePriority = ["icon", "logo", "poster", "hero", "photo", "avatar"];
  return [...media].sort((a, b) => {
    const aPriority = rolePriority.indexOf(a.role);
    const bPriority = rolePriority.indexOf(b.role);
    return (aPriority < 0 ? rolePriority.length : aPriority)
      - (bPriority < 0 ? rolePriority.length : bPriority);
  }).find(item => (
    typeof item.url === "string"
      && item.url.length > 0
  )) || null;
}

function filteredURL(
  baseURL,
  { cursor = null, limit = null, bounds = state.bounds, zoom = null } = {},
) {
  const url = new URL(baseURL, window.location.href);
  url.search = "";
  for (const catalog of state.selectedCatalogs) url.searchParams.append("catalogs", catalog);
  const query = state.query.trim();
  if (query) url.searchParams.set("query", query);
  url.searchParams.set("dates", state.dates);
  if (state.clusterCell) url.searchParams.set("cell", state.clusterCell);
  if (bounds) {
    for (const [name, value] of Object.entries(bounds)) {
      url.searchParams.set(name, String(value));
    }
  }
  if (Number.isFinite(zoom)) url.searchParams.set("zoom", String(zoom));
  if (cursor) url.searchParams.set("cursor", cursor);
  if (limit) url.searchParams.set("limit", String(limit));
  return url;
}

async function fetchJSON(url, signal) {
  const startedAt = performance.now();
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal,
  });
  if (!response.ok) throw new Error(`${url.pathname} returned ${response.status}`);
  const value = await response.json();
  const resource = performance.getEntriesByName(response.url, "resource").at(-1);
  return {
    value,
    transferDurationMilliseconds: performance.now() - startedAt,
    compressedBytes: resource?.encodedBodySize || Number(response.headers.get("content-length")) || null,
  };
}

async function searchMapFor(events, signal) {
  if (!events.length) return { events: [], clusters: [] };
  const url = new URL(config.mapItemsURL, window.location.href);
  for (const event of events) url.searchParams.append("uris", event.uri);
  url.searchParams.set("zoom", String(Math.min(18, state.map?.getZoom() ?? config.initialZoom)));
  const response = await fetchJSON(url, signal);
  return { ...response.value, metrics: { ...response.value.metrics,
    compressedBytes: response.compressedBytes,
    transferDurationMilliseconds: response.transferDurationMilliseconds,
  } };
}

async function loadData({ bounds = currentMapBounds(), focusNow = false, cursor = null, pageCursors = [] } = {}) {
  const requestID = ++state.requestID;
  state.displayStartedAt = performance.now();
  state.requestController?.abort();
  state.mapRequestController?.abort();
  state.mapRequestID++;
  const controller = state.requestController = new AbortController();
  const search = Boolean(state.query.trim());
  state.bounds = bounds;
  updateBrowseTiles();
  els.searchArea.hidden = !search;
  els.searchEverywhere.hidden = !search || !state.searchBounds;
  els.listHeading.textContent = search ? (state.searchBounds ? "Search results in selected area" : "Search results everywhere") : (state.clusterCell ? "Events in this cluster" : "Events in view");
  if (!state.selectedCatalogs.size) {
    state.cursor = null;
    state.currentCursor = null;
    state.pageCursors = [];
    state.highlightedMembers = null;
    els.showPageResults.hidden = true;
    els.eventList.setAttribute("aria-busy", "false");
    replaceData([], [], [], { source: "No catalogs selected", focusNow: false });
    return;
  }
  els.dataStatus.textContent = search ? "Searching events, artists, and places…" : "Loading events in view…";
  els.eventList.setAttribute("aria-busy", "true");
  els.loadMore.disabled = true;
  els.previousPage.disabled = true;
  try {
    const response = await fetchJSON(filteredURL(config.xrpcURL, {
      limit: 50, cursor, bounds: search ? state.searchBounds : (state.clusterCell ? null : bounds),
    }), controller.signal);
    if (!Array.isArray(response.value.events)) throw new Error("Missing event summaries");
    const map = search ? await searchMapFor(response.value.events, controller.signal) : { events: [], clusters: [] };
    if (requestID !== state.requestID) return;
    state.displayedRequestID = requestID;
    state.currentCursor = cursor;
    state.pageCursors = pageCursors;
    state.searchClusterMembers = map.clusterMembers || {};
    state.highlightedMembers = null;
    els.showPageResults.hidden = true;
    state.cursor = response.value.cursor || null;
    state.mapItemMetrics = { ...map.metrics, listTransferMilliseconds: response.transferDurationMilliseconds, listCompressedBytes: response.compressedBytes };
    replaceData(response.value.events, map.events, map.clusters, { source: search ? "Search" : "OME AppView", focusNow });
    if (search && state.fitSearch) {
      state.fitSearch = false;
      const located = state.listEvents.filter(event => event.coordinates && Math.abs(event.coordinates[1]) <= 85.051129);
      if (located.length && state.mapReady) {
        const bounds = new maplibregl.LngLatBounds(located[0].coordinates, located[0].coordinates);
        for (const event of located) bounds.extend(event.coordinates);
        state.map.fitBounds(bounds, { padding: 75, maxZoom: 12, duration: 500 });
      }
    }
  } catch (error) {
    if (error.name === "AbortError" || requestID !== state.requestID) return;
    els.dataStatus.textContent = "Could not update results. Previous results are still shown.";
    console.error(error);
  } finally {
    if (requestID === state.requestID) {
      els.eventList.setAttribute("aria-busy", "false");
      els.loadMore.disabled = false;
      els.previousPage.disabled = false;
    }
  }
}

async function loadMapItems() {
  if (!state.query.trim() || state.displayedRequestID !== state.requestID) return;
  const requestID = ++state.mapRequestID;
  state.mapRequestController?.abort();
  const controller = state.mapRequestController = new AbortController();
  const page = state.listEvents;
  try {
    const map = await searchMapFor(page, controller.signal);
    if (requestID !== state.mapRequestID || page !== state.listEvents) return;
    state.searchClusterMembers = map.clusterMembers || {};
    state.mapItemMetrics = { ...state.mapItemMetrics, ...map.metrics };
    state.mapPoints = map.events.map(normalizeEvent).filter(event => event?.coordinates);
    state.mapClusters = map.clusters.map(normalizeCluster).filter(Boolean);
    updateMapData();
  } catch (error) {
    if (error.name !== "AbortError") els.dataStatus.textContent = "Search results loaded; their map could not be updated.";
  }
}

function replaceData(events, points, clusters, { source, focusNow }) {
  state.listEvents = events.map(normalizeEvent).filter(Boolean);
  state.mapPoints = points.map(normalizeEvent).filter(event => event?.coordinates);
  state.mapClusters = clusters.map(normalizeCluster).filter(Boolean);
  state.hasMore = Boolean(state.cursor);
  els.loadMore.hidden = !state.hasMore;
  els.previousPage.hidden = !state.pageCursors.length;
  const located = state.listEvents.filter(event => event.coordinates && Math.abs(event.coordinates[1]) <= 85.051129).length;
  els.dataStatus.textContent = state.query.trim()
    ? `${events.length} results on this page · ${located} located · ${source}`
    : `${events.length} events on this page · ${state.dates === "current" ? "Current and upcoming" : "All dates"}`;
  renderEventList();
  updateMapData();
  if (focusNow) focusFirstCurrentEvent();
  else if (state.selectedID && !eventForID(state.selectedID)) selectEvent(null, false);
}

async function loadMoreEvents() {
  if (!state.cursor) return;
  state.fitSearch = Boolean(state.query.trim());
  await loadData({ cursor: state.cursor, pageCursors: [...state.pageCursors, state.currentCursor] });
}

function browseTileURL() {
  const query = new URLSearchParams();
  for (const catalog of [...state.selectedCatalogs].sort()) query.append("catalogs", catalog);
  query.set("dates", state.dates);
  return `${window.location.origin}/map/events/{z}/{x}/{y}.mvt?${query}`;
}

function updateBrowseTiles(force = false) {
  if (!state.mapReady || !state.map.getSource("calendar-browse")) return;
  const searching = Boolean(state.query.trim());
  for (const suffix of ["clusters", "cluster-count", "points", "hit-targets"]) {
    state.map.setLayoutProperty("browse-" + suffix, "visibility", !searching && state.selectedCatalogs.size ? "visible" : "none");
    state.map.setLayoutProperty("event-" + suffix, "visibility", searching ? "visible" : "none");
  }
  const url = browseTileURL();
  if (!searching && state.selectedCatalogs.size && (force || url !== state.tileFilterKey)) {
    state.tileFilterKey = url;
    state.map.getSource("calendar-browse").setTiles([url]);
  }
  syncVisibleImageMarkers();
}

function eventForID(id) {
  return state.listEvents.find(event => event.uri === id)
    || state.mapPoints.find(event => event.uri === id)
    || null;
}

function visibleEvents() {
  return state.highlightedMembers ? state.listEvents.filter(event => state.highlightedMembers.has(event.uri)) : state.listEvents;
}

function focusFirstCurrentEvent() {
  const event = visibleEvents()[0];
  if (!event) return selectEvent(null, false);
  selectEvent(event.uri, false);
  document.querySelector(`.event-card[data-id="${CSS.escape(event.uri)}"] button`)?.focus();
}

function dateParts(event) {
  if (!event.date) return { month: "TBA", day: "—", weekday: "" };
  return {
    month: formatterFor(event, { month: "short" }).format(event.date),
    day: formatterFor(event, { day: "2-digit" }).format(event.date),
    weekday: formatterFor(event, { weekday: "short" }).format(event.date),
  };
}

function offsetMinutesFromToken(value) {
  const match = /([+-])(\d{2}):?(\d{2})$/.exec(value || "");
  if (!match) return /^(?:GMT|UTC)$/i.test(value || "") ? 0 : null;
  const sign = match[1] === "+" ? 1 : -1;
  return sign * (Number(match[2]) * 60 + Number(match[3]));
}

function offsetMinutesFromTimestamp(value) {
  if (/Z$/i.test(value || "")) return 0;
  return offsetMinutesFromToken(value);
}

function offsetMinutesInZone(date, timeZone) {
  const timeZoneName = new Intl.DateTimeFormat("en-US", {
    timeZone,
    timeZoneName: "longOffset",
  }).formatToParts(date).find(part => part.type === "timeZoneName")?.value;
  return offsetMinutesFromToken(timeZoneName);
}

function formatterFor(event, options, timestamp = event.startsAt) {
  if (event.timezone) {
    try {
      return new Intl.DateTimeFormat(undefined, { ...options, timeZone: event.timezone });
    } catch {
      // An invalid zone still gets the event's explicit timestamp offset below.
    }
  }

  const offset = offsetMinutesFromTimestamp(timestamp) ?? 0;
  const utcFormatter = new Intl.DateTimeFormat(undefined, { ...options, timeZone: "UTC" });
  return { format: date => utcFormatter.format(new Date(date.valueOf() + offset * 60_000)) };
}

function eventOffsetMinutes(event, date, timestamp) {
  if (event.timezone) {
    try {
      return offsetMinutesInZone(date, event.timezone);
    } catch {
      // Fall back to the offset carried by this event timestamp.
    }
  }
  return offsetMinutesFromTimestamp(timestamp) ?? 0;
}

function eventZoneAbbreviation(event, date, timestamp) {
  if (event.timezone) {
    try {
      return new Intl.DateTimeFormat(undefined, {
        timeZone: event.timezone,
        timeZoneName: "short",
      }).formatToParts(date).find(part => part.type === "timeZoneName")?.value;
    } catch {
      // Use the explicit timestamp offset when the event's zone is unavailable.
    }
  }

  const offset = offsetMinutesFromTimestamp(timestamp) ?? 0;
  if (offset === 0) return "UTC";
  const sign = offset > 0 ? "+" : "−";
  const hours = String(Math.floor(Math.abs(offset) / 60)).padStart(2, "0");
  const minutes = String(Math.abs(offset) % 60).padStart(2, "0");
  return `UTC${sign}${hours}:${minutes}`;
}

function viewerOffsetMinutes(date) {
  const timeZone = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  return timeZone ? offsetMinutesInZone(date, timeZone) : -date.getTimezoneOffset();
}

function canonicalTimeZone(timeZone) {
  try {
    return new Intl.DateTimeFormat("en-US", { timeZone }).resolvedOptions().timeZone;
  } catch {
    return null;
  }
}

function viewerNeedsEventTimeZone(event, date, timestamp) {
  const viewerTimeZone = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  const eventTimeZone = event.timezone && canonicalTimeZone(event.timezone);
  if (viewerTimeZone && eventTimeZone) {
    return canonicalTimeZone(viewerTimeZone) !== eventTimeZone;
  }
  return eventOffsetMinutes(event, date, timestamp) !== viewerOffsetMinutes(date);
}

function formatEventTime(event) {
  if (event.dateOnly) return "Time not specified";
  if (!event.date) return "Time to be announced";
  const start = formatterFor(event, { hour: "numeric", minute: "2-digit" }).format(event.date);
  const startNeedsZone = viewerNeedsEventTimeZone(event, event.date, event.startsAt);
  const startZone = startNeedsZone ? eventZoneAbbreviation(event, event.date, event.startsAt) : null;
  if (!event.endDate) return startZone ? `${start} ${startZone}` : start;

  const end = formatterFor(event, { hour: "numeric", minute: "2-digit" }, event.endsAt).format(event.endDate);
  const endNeedsZone = viewerNeedsEventTimeZone(event, event.endDate, event.endsAt);
  const endZone = endNeedsZone ? eventZoneAbbreviation(event, event.endDate, event.endsAt) : null;
  if (startZone && startZone === endZone) return `${start} – ${end} ${startZone}`;
  return `${start}${startZone ? ` ${startZone}` : ""} – ${end}${endZone ? ` ${endZone}` : ""}`;
}

function formatCalloutDate(event) {
  if (!event.date) return "Date to be announced";
  const date = formatterFor(event, { month: "short", day: "numeric" }).format(event.date);
  return `${date} · ${formatEventTime(event)}`;
}

function initials(name) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(word => word[0]).join("").toUpperCase() || "OME";
}

function renderEventList() {
  const events = visibleEvents();
  els.eventList.replaceChildren();
  els.emptyState.hidden = events.length > 0;
  els.resultCount.textContent = `${events.length} event${events.length === 1 ? "" : "s"}`;

  events.forEach(event => {
    const card = els.eventCardTemplate.content.firstElementChild.cloneNode(true);
    const parts = dateParts(event);
    card.dataset.id = event.uri;
    card.classList.toggle("selected", event.uri === state.selectedID);
    const button = card.querySelector("button");
    button.setAttribute("aria-label", `${event.name}, ${formatCalloutDate(event)}, ${event.locationSummary}`);
    button.setAttribute("aria-expanded", String(event.uri === state.selectedID));
    card.querySelector(".event-month").textContent = parts.month;
    card.querySelector(".event-day").textContent = parts.day;
    card.querySelector(".event-weekday").textContent = parts.weekday;

    const art = card.querySelector(".event-art");
    art.style.setProperty("--card-color", event.color);
    card.querySelector(".event-monogram").textContent = initials(event.name);
    if (event.image) {
      art.classList.add("has-image");
      if (event.imageRenderKind === "transparent") {
        art.classList.add("transparent-image");
        const image = document.createElement("img");
        image.src = event.image;
        image.alt = "";
        art.append(image);
      } else {
        art.style.backgroundImage = `url("${escapeCSSURL(event.image)}")`;
      }
    }

    card.querySelector(".event-name").textContent = event.name;
    card.querySelector(".event-location span").textContent = event.locationSummary;
    card.querySelector(".event-time").textContent = formatEventTime(event);
    card.querySelector(".event-distance").textContent = distanceLabel(event);
    button.addEventListener("click", () => selectEvent(event.uri, true));
    if (event.uri === state.selectedID) {
      const detail = card.querySelector(".event-detail");
      detail.hidden = false;
      renderEventDetail(detail, event);
    }
    els.eventList.append(card);
  });
  requestAnimationFrame(updateConnector);
}

function renderEventDetail(container, summary) {
  const event = state.selectedDetails?.uri === summary.uri
    ? normalizeEvent(state.selectedDetails)
    : null;
  if (!event) {
    container.innerHTML = `<p class="event-detail-status">Loading event details…</p>`;
    return;
  }
  const locations = (event.locations || []).map(location => {
    const value = [location.name, location.street, location.locality, location.region, location.postalCode, location.country]
      .filter(Boolean).join(", ");
    return value ? `<li>${escapeHTML(value)}</li>` : "";
  }).join("");
  const links = (event.links || []).filter(link => (
    link.source !== "app.openmusicevent.eventViewer"
  )).map(link => (
    `<li><a href="${escapeAttribute(link.uri)}" rel="external">${escapeHTML(link.name || link.uri)}</a></li>`
  )).join("");
  const sourceLink = sourceRecordLink(event);
  const enterEventLink = eventViewerLink(event);
  container.innerHTML = `
    <div class="event-detail-grid">
      <div>
        <strong>${escapeHTML(formatCalloutDate(event))}</strong>
        <span>${escapeHTML(event.timezone || "Event time zone not supplied")}</span>
      </div>
      <div>
        <strong>${escapeHTML(event.organizer?.displayName || event.organizer?.handle || event.organizer?.id || "Organizer")}</strong>
        <span>Organizer</span>
      </div>
    </div>
    ${locations ? `<ul class="event-detail-locations">${locations}</ul>` : ""}
    ${event.description ? `<p class="event-detail-description">${escapeHTML(event.description)}</p>` : ""}
    ${(links || sourceLink) ? `<ul class="event-detail-links">${links}${sourceLink}</ul>` : ""}
    ${enterEventLink}
  `;
}

function eventViewerLink(event) {
  const match = /^at:\/\/([^/]+)\/events\.openmusic\.event\/([^/]+)$/.exec(event.uri);
  const hasViewer = (event.links || []).some(link => (
    link.source === "app.openmusicevent.eventViewer"
  ));
  if (!match || !hasViewer) return "";
  return `<a class="event-enter-button" href="/record/${encodeURIComponent(match[1])}/${encodeURIComponent(match[2])}">Enter Event</a>`;
}

function sourceRecordLink(event) {
  if (/^at:\/\/[^/]+\/events\.openmusic\.event\/[^/]+$/.test(event.uri)) return "";
  return `<li><a href="${escapeAttribute(event.uri)}">Open source record</a></li>`;
}

function eventGeoJSON() {
  return {
    type: "FeatureCollection",
    features: [
      ...state.mapPoints.map(event => ({
        type: "Feature",
        id: event.uri,
        geometry: { type: "Point", coordinates: event.coordinates },
        properties: {
          kind: "event",
          uri: event.uri,
          name: event.name,
          color: event.color,
          markerImage: event.markerImage || "",
          markerImageRenderKind: event.markerImageRenderKind || "",
        },
      })),
      ...state.mapClusters.map(cluster => ({
        type: "Feature",
        id: cluster.id,
        geometry: { type: "Point", coordinates: cluster.coordinates },
        properties: {
          kind: "cluster",
          clusterID: cluster.id,
          count: cluster.count,
          expansionZoom: cluster.expansionZoom,
          north: cluster.bounds.north,
          south: cluster.bounds.south,
          east: cluster.bounds.east,
          west: cluster.bounds.west,
        },
      })),
    ],
  };
}

function installEventLayers() {
  state.map.addSource("calendar-events", { type: "geojson", data: eventGeoJSON() });
  state.tileFilterKey = browseTileURL();
  state.map.addSource("calendar-browse", { type: "vector", tiles: [state.tileFilterKey], minzoom: 0, maxzoom: 18 });
  for (const prefix of ["event", "browse"]) {
    const source = prefix === "event" ? { source: "calendar-events" } : { source: "calendar-browse", "source-layer": "events" };
  state.map.addLayer({
    id: prefix + "-clusters",
    type: "circle",
    ...source,
    filter: ["==", ["get", "kind"], "cluster"],
    paint: {
      "circle-color": "#9a4eff",
      "circle-radius": ["step", ["get", "count"], 20, 10, 25, 100, 31],
      "circle-stroke-width": 4,
      "circle-stroke-color": "rgba(5, 6, 14, .86)",
      "circle-opacity": .88,
    },
  });
  state.map.addLayer({
    id: prefix + "-cluster-count",
    type: "symbol",
    ...source,
    filter: ["==", ["get", "kind"], "cluster"],
    layout: { "text-field": ["to-string", ["get", "count"]], "text-size": 12, "text-font": ["Noto Sans Regular"] },
    paint: { "text-color": "#ffffff" },
  });
  state.map.addLayer({
    id: prefix + "-points",
    type: "circle",
    ...source,
    filter: ["==", ["get", "kind"], "event"],
    paint: {
      "circle-color": ["get", "color"],
      "circle-radius": 10,
      "circle-stroke-width": 4,
      "circle-stroke-color": "rgba(5, 6, 14, .9)",
    },
  });
  state.map.addLayer({
    id: prefix + "-hit-targets",
    type: "circle",
    ...source,
    filter: ["==", ["get", "kind"], "event"],
    paint: { "circle-radius": 24, "circle-opacity": 0 },
  });

  state.map.on("click", prefix + "-clusters", event => {
    openCluster(event.features?.[0]).catch(error => console.error(error));
  });
  state.map.on("click", prefix + "-hit-targets", event => {
    const uri = event.features?.[0]?.properties?.uri;
    if (uri) {
      rememberTileEvent(event.features[0]);
      selectEvent(uri, false);
    }
  });
  for (const layer of [prefix + "-clusters", prefix + "-hit-targets"]) {
    state.map.on("mouseenter", layer, () => { state.map.getCanvas().style.cursor = "pointer"; });
    state.map.on("mouseleave", layer, () => { state.map.getCanvas().style.cursor = ""; });
  }
  }
}

function initializeMap() {
  if (!window.maplibregl) {
    els.mapFallback.removeAttribute("hidden");
    return;
  }

  try {
    state.map = new maplibregl.Map({
      container: "map",
      style: config.mapStyle,
      center: config.initialCenter,
      zoom: config.initialZoom,
      minZoom: .45,
      maxZoom: 18,
      renderWorldCopies: false,
      attributionControl: true,
      collectResourceTiming: true,
    });
    state.map.on("data", event => {
      const timings = event.resourceTiming || event.tile?.resourceTiming;
      if (event.sourceId === "calendar-browse" && Array.isArray(timings)) {
        const distinct = new Map([...state.tileTimings, ...timings].map(timing => [`${timing.name}:${timing.startTime}`, timing]));
        state.tileTimings = [...distinct.values()].slice(-100);
      }
    });
    state.map.on("render", () => {
      if (state.mapReady && state.firstVisibleMarkersMilliseconds == null) recordBrowseMetrics();
    });
    // Style readiness is sufficient for adding layers; do not wait for every basemap tile.
    state.map.once("style.load", () => {
      state.mapReady = true;
      els.mapFallback.hidden = true;
      if (typeof state.map.setProjection === "function") {
        state.map.setProjection({ type: "globe" });
      }
      if (typeof state.map.setSky === "function") {
        state.map.setSky({
          "sky-color": "#070913",
          "horizon-color": "#b64dff",
          "sky-horizon-blend": 0.8,
          "atmosphere-blend": [
            "interpolate", ["linear"], ["zoom"],
            0, 1,
            5, 1,
            7, 0,
          ],
        });
      }
      styleGlobeMap();
      const firstSymbolLayer = state.map.getStyle().layers.find(layer => layer.type === "symbol");
      state.map.addLayer(createGlobeRimLayer(), firstSymbolLayer?.id);
      installEventLayers();
      updateBrowseTiles();
      updateMapData();
      if (!state.query.trim()) loadData({ bounds: currentMapBounds() }).catch(console.error);
      state.map.on("idle", syncVisibleImageMarkers);
      state.map.on("idle", recordBrowseMetrics);
      requestAnimationFrame(updateConnector);
    });
    state.map.on("move", () => {
      updateConnector();
    });
    state.map.on("moveend", () => {
      syncVisibleImageMarkers();
      const viewport = currentMapViewport();
      if (state.skipNextMoveReload) {
        state.skipNextMoveReload = false;
        scheduleMapReload(viewport);
        return;
      }
      if (state.query.trim()) scheduleMapReload(viewport);
      else { state.clusterCell = null; scheduleReload(viewport); }
    });
    state.map.on("resize", updateConnector);
    state.map.on("error", event => {
      console.info("Map style or tiles unavailable.", event.error);
      if (!state.mapReady) els.mapFallback.removeAttribute("hidden");
    });
  } catch (error) {
    console.info("MapLibre could not start.", error);
    els.mapFallback.removeAttribute("hidden");
  }
}

async function openCluster(feature) {
  if (!feature) return;
  const zoom = Number(feature.properties.expansionZoom);
  if (!state.query.trim()) {
    state.clusterCell = feature.properties.clusterID;
    state.selectedID = null;
    state.selectedDetails = null;
    await loadData({ bounds: currentMapBounds() });
    state.skipNextMoveReload = true;
  } else {
    const members = state.searchClusterMembers[feature.properties.clusterID];
    if (members) {
      state.highlightedMembers = new Set(members);
      els.showPageResults.hidden = false;
      renderEventList();
    }
  }
  state.map.easeTo({ center: feature.geometry.coordinates, zoom, essential: true });
  els.eventList.querySelector("button")?.focus();
}

function rememberTileEvent(feature) {
  const uri = feature.properties?.uri;
  if (!uri || eventForID(uri)) return;
  const event = normalizeEvent({ ...feature.properties, uri,
    latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0],
    markerMedia: { url: feature.properties.markerImage, renderKind: feature.properties.markerImageRenderKind },
  });
  if (event) state.mapPoints.push(event);
}

function syncVisibleImageMarkers() {
  if (!state.mapReady || !state.map.getLayer("event-hit-targets")) return;
  const features = state.map.queryRenderedFeatures({ layers: ["event-hit-targets", "browse-hit-targets"] });
  const visible = new Map();
  if (!state.query.trim()) state.mapPoints = [];
  for (const feature of features) {
    rememberTileEvent(feature);
    const uri = feature.properties?.uri;
    const event = eventForID(uri);
    if (event?.markerImage) visible.set(uri, event);
  }
  for (const [uri, event] of visible) {
    let marker = state.imageMarkers.get(uri);
    if (!marker) {
      const element = document.createElement("button");
      element.type = "button";
      element.className = "event-marker";
      element.style.setProperty("--marker-color", event.color);
      element.setAttribute("aria-label", `${event.name} map marker`);
      const image = document.createElement("img");
      image.loading = "lazy";
      image.decoding = "async";
      image.src = event.markerImage;
      image.addEventListener("error", () => { element.hidden = true; });
      image.alt = "";
      image.className = event.markerImageRenderKind === "transparent" ? "transparent-image" : "full-image";
      element.append(image);
      element.addEventListener("click", click => {
        click.stopPropagation();
        selectEvent(uri, false);
      });
      marker = new maplibregl.Marker({ element, anchor: "center" })
        .setLngLat(event.coordinates)
        .addTo(state.map);
      state.imageMarkers.set(uri, marker);
    }
    marker.getElement().classList.toggle("selected", uri === state.selectedID);
  }
  for (const [uri, marker] of state.imageMarkers) {
    if (visible.has(uri)) continue;
    marker.remove();
    state.imageMarkers.delete(uri);
  }
}

function globalMapBounds() {
  return { north: 90, south: -90, east: 180, west: -180 };
}

function currentMapBounds() {
  if (!state.mapReady) return globalMapBounds();
  const bounds = state.map.getBounds();
  const westUnwrapped = bounds.getWest();
  const eastUnwrapped = bounds.getEast();
  if (eastUnwrapped - westUnwrapped >= 355) return globalMapBounds();
  return {
    north: Math.min(90, bounds.getNorth()),
    south: Math.max(-90, bounds.getSouth()),
    east: normalizeLongitude(eastUnwrapped),
    west: normalizeLongitude(westUnwrapped),
  };
}

function currentMapViewport() {
  return {
    bounds: currentMapBounds(),
    zoom: state.map?.getZoom() ?? config.initialZoom,
  };
}

function normalizeLongitude(value) {
  return ((value + 180) % 360 + 360) % 360 - 180;
}

function scheduleReload(options = {}) {
  window.clearTimeout(state.reloadTimer);
  state.reloadTimer = window.setTimeout(() => {
    loadData(options).catch(error => console.error(error));
  }, 250);
}

function scheduleMapReload(options) {
  window.clearTimeout(state.mapReloadTimer);
  state.mapReloadTimer = window.setTimeout(() => {
    loadMapItems(options).catch(error => console.error(error));
  }, 250);
}

function createGlobeRimLayer() {
  const longitudeSteps = 128;
  const latitudeSteps = 64;
  const vertices = [];
  const indices = [];

  for (let latitude = 0; latitude <= latitudeSteps; latitude += 1) {
    const geographicLatitude = 89.5 - (179 * latitude / latitudeSteps);
    const latitudeRadians = geographicLatitude * Math.PI / 180;
    const mercatorY = .5 - Math.log(Math.tan(Math.PI / 4 + latitudeRadians / 2)) / (2 * Math.PI);
    for (let longitude = 0; longitude <= longitudeSteps; longitude += 1) {
      vertices.push(longitude / longitudeSteps, mercatorY);
    }
  }

  for (let latitude = 0; latitude < latitudeSteps; latitude += 1) {
    for (let longitude = 0; longitude < longitudeSteps; longitude += 1) {
      const southwest = latitude * (longitudeSteps + 1) + longitude;
      const southeast = southwest + 1;
      const northwest = southwest + longitudeSteps + 1;
      const northeast = northwest + 1;
      indices.push(southwest, southeast, northwest, southeast, northeast, northwest);
    }
  }

  const layer = {
    id: "ome-globe-rim",
    type: "custom",
    renderingMode: "2d",
    shaderPrograms: new Map(),
    vertices: new Float32Array(vertices),
    indices: new Uint16Array(indices),

    getProgram(gl, shaderData) {
      const cached = this.shaderPrograms.get(shaderData.variantName);
      if (cached) return cached;

      const vertexSource = `#version 300 es
${shaderData.vertexShaderPrelude}
${shaderData.define}
in vec2 a_pos;
out float v_horizon_distance;
void main() {
  vec3 sphere_position = projectToSphere(a_pos);
  v_horizon_distance = 1.0 - (dot(sphere_position, u_projection_clipping_plane.xyz)
    + u_projection_clipping_plane.w);
  gl_Position = projectTile(a_pos);
}`;
      const fragmentSource = `#version 300 es
precision highp float;
in float v_horizon_distance;
uniform vec4 u_color;
uniform float u_band_width;
uniform float u_rim_opacity;
out vec4 fragColor;
void main() {
  float edge = 1.0 - smoothstep(u_band_width * 0.5, u_band_width, abs(v_horizon_distance));
  if (edge <= 0.001) discard;
  fragColor = vec4(u_color.rgb, u_color.a * edge * u_rim_opacity);
}`;
      const vertexShader = compileGlobeShader(gl, gl.VERTEX_SHADER, vertexSource);
      const fragmentShader = compileGlobeShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
      const program = gl.createProgram();
      gl.attachShader(program, vertexShader);
      gl.attachShader(program, fragmentShader);
      gl.linkProgram(program);
      gl.deleteShader(vertexShader);
      gl.deleteShader(fragmentShader);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        const message = gl.getProgramInfoLog(program) || "Unknown globe-rim shader link error";
        gl.deleteProgram(program);
        throw new Error(message);
      }

      const compiled = {
        program,
        position: gl.getAttribLocation(program, "a_pos"),
        projection: gl.getUniformLocation(program, "u_projection_matrix"),
        fallback: gl.getUniformLocation(program, "u_projection_fallback_matrix"),
        tile: gl.getUniformLocation(program, "u_projection_tile_mercator_coords"),
        clipping: gl.getUniformLocation(program, "u_projection_clipping_plane"),
        transition: gl.getUniformLocation(program, "u_projection_transition"),
        color: gl.getUniformLocation(program, "u_color"),
        bandWidth: gl.getUniformLocation(program, "u_band_width"),
        opacity: gl.getUniformLocation(program, "u_rim_opacity"),
      };
      this.shaderPrograms.set(shaderData.variantName, compiled);
      return compiled;
    },

    onAdd(_map, gl) {
      const previousVAO = gl.getParameter(gl.VERTEX_ARRAY_BINDING);
      const previousBuffer = gl.getParameter(gl.ARRAY_BUFFER_BINDING);
      this.vertexArray = gl.createVertexArray();
      gl.bindVertexArray(this.vertexArray);
      this.vertexBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, this.vertices, gl.STATIC_DRAW);
      this.indexBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.indexBuffer);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, this.indices, gl.STATIC_DRAW);
      gl.bindVertexArray(previousVAO);
      gl.bindBuffer(gl.ARRAY_BUFFER, previousBuffer);
    },

    render(gl, args) {
      const shader = this.getProgram(gl, args.shaderData);
      const projection = args.defaultProjectionData;
      if (projection.projectionTransition < 0.01) return;
      const previous = {
        program: gl.getParameter(gl.CURRENT_PROGRAM),
        vertexArray: gl.getParameter(gl.VERTEX_ARRAY_BINDING),
        arrayBuffer: gl.getParameter(gl.ARRAY_BUFFER_BINDING),
        elementBuffer: gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING),
        blendEnabled: gl.isEnabled(gl.BLEND),
        blendSourceRGB: gl.getParameter(gl.BLEND_SRC_RGB),
        blendDestinationRGB: gl.getParameter(gl.BLEND_DST_RGB),
        blendSourceAlpha: gl.getParameter(gl.BLEND_SRC_ALPHA),
        blendDestinationAlpha: gl.getParameter(gl.BLEND_DST_ALPHA),
        blendEquationRGB: gl.getParameter(gl.BLEND_EQUATION_RGB),
        blendEquationAlpha: gl.getParameter(gl.BLEND_EQUATION_ALPHA),
        cullEnabled: gl.isEnabled(gl.CULL_FACE),
        depthEnabled: gl.isEnabled(gl.DEPTH_TEST),
        depthWrite: gl.getParameter(gl.DEPTH_WRITEMASK),
      };
      gl.bindVertexArray(this.vertexArray);
      gl.useProgram(shader.program);
      gl.uniformMatrix4fv(shader.projection, false, projection.mainMatrix);
      gl.uniformMatrix4fv(shader.fallback, false, projection.fallbackMatrix);
      gl.uniform4fv(shader.tile, projection.tileMercatorCoords);
      gl.uniform4fv(shader.clipping, projection.clippingPlane);
      gl.uniform1f(shader.transition, projection.projectionTransition);
      gl.uniform1f(shader.opacity, projection.projectionTransition);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
      gl.enableVertexAttribArray(shader.position);
      gl.vertexAttribPointer(shader.position, 2, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.indexBuffer);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.disable(gl.CULL_FACE);

      gl.uniform1f(shader.bandWidth, 0.032);
      gl.uniform4f(shader.color, 0.64, 0.20, 1, 0.2);
      gl.drawElements(gl.TRIANGLES, this.indices.length, gl.UNSIGNED_SHORT, 0);

      gl.uniform1f(shader.bandWidth, 0.009);
      gl.uniform4f(shader.color, 0.77, 0.45, 1, 0.78);
      gl.drawElements(gl.TRIANGLES, this.indices.length, gl.UNSIGNED_SHORT, 0);

      gl.bindVertexArray(previous.vertexArray);
      gl.bindBuffer(gl.ARRAY_BUFFER, previous.arrayBuffer);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, previous.elementBuffer);
      gl.useProgram(previous.program);
      gl.blendFuncSeparate(
        previous.blendSourceRGB,
        previous.blendDestinationRGB,
        previous.blendSourceAlpha,
        previous.blendDestinationAlpha,
      );
      gl.blendEquationSeparate(previous.blendEquationRGB, previous.blendEquationAlpha);
      gl.depthMask(previous.depthWrite);
      setGlCapability(gl, gl.BLEND, previous.blendEnabled);
      setGlCapability(gl, gl.CULL_FACE, previous.cullEnabled);
      setGlCapability(gl, gl.DEPTH_TEST, previous.depthEnabled);
    },

    onRemove(_map, gl) {
      gl.deleteVertexArray(this.vertexArray);
      gl.deleteBuffer(this.vertexBuffer);
      gl.deleteBuffer(this.indexBuffer);
      for (const shader of this.shaderPrograms.values()) gl.deleteProgram(shader.program);
      this.shaderPrograms.clear();
    },
  };

  return layer;
}

function setGlCapability(gl, capability, enabled) {
  if (enabled) gl.enable(capability);
  else gl.disable(capability);
}

function compileGlobeShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const message = gl.getShaderInfoLog(shader) || "Unknown globe-rim shader compile error";
    gl.deleteShader(shader);
    throw new Error(message);
  }
  return shader;
}

function styleGlobeMap() {
  if (!state.mapReady) return;
  for (const layer of state.map.getStyle().layers || []) {
    const name = `${layer.id} ${layer["source-layer"] || ""}`.toLowerCase();
    if (layer.type === "background") {
      state.map.setPaintProperty(layer.id, "background-color", "#030711");
      continue;
    }
    if (layer.type === "fill") {
      const color = /water|ocean|lake|river/.test(name)
        ? "#07172a"
        : /wood|forest|park|grass|landcover|landuse/.test(name)
          ? "#102033"
          : "#152136";
      state.map.setPaintProperty(layer.id, "fill-color", color);
      if (layer.paint?.["fill-outline-color"] !== undefined) {
        state.map.setPaintProperty(layer.id, "fill-outline-color", "#1c314a");
      }
      continue;
    }
    if (layer.type === "line") {
      const color = /boundary|admin/.test(name) ? "#324a68" : "#1c3048";
      state.map.setPaintProperty(layer.id, "line-color", color);
      if (layer.paint?.["line-opacity"] !== undefined) {
        state.map.setPaintProperty(layer.id, "line-opacity", .52);
      }
      continue;
    }
    if (layer.type === "symbol") {
      if (layer.layout?.["text-field"] !== undefined) {
        state.map.setPaintProperty(layer.id, "text-color", "#879ab7");
        state.map.setPaintProperty(layer.id, "text-halo-color", "#030711");
        state.map.setPaintProperty(layer.id, "text-halo-width", 1.1);
      }
      if (layer.layout?.["icon-image"] !== undefined) {
        state.map.setPaintProperty(layer.id, "icon-opacity", .45);
      }
    }
  }
}

function updateMapData() {
  if (!state.mapReady) return;
  const source = state.map.getSource("calendar-events");
  if (!source) return;
  state.pendingMapReadyAt = performance.now();
  source.setData(eventGeoJSON());
  state.map.once("idle", () => {
    syncVisibleImageMarkers();
    if (state.pendingMapReadyAt == null) return;
    const mapLibreReadyDurationMilliseconds = performance.now() - state.pendingMapReadyAt;
    state.pendingMapReadyAt = null;
    if (!state.query.trim()) { recordBrowseMetrics(); return; }
    const metrics = {
      candidateCount: state.mapItemMetrics?.candidateCount ?? state.mapPoints.length,
      itemCount: state.mapItemMetrics?.itemCount ?? state.mapPoints.length + state.mapClusters.length,
      compressedResponseBytes: state.mapItemMetrics?.compressedBytes ?? "unavailable",
      databaseDurationMilliseconds: state.mapItemMetrics?.databaseDurationMilliseconds ?? "unavailable",
      clusteringDurationMilliseconds: state.mapItemMetrics?.clusteringDurationMilliseconds ?? "unavailable",
      transferDurationMilliseconds: state.mapItemMetrics?.transferDurationMilliseconds ?? "unavailable",
      mapLibreReadyDurationMilliseconds,
    };
    window.OME_GLOBE_METRICS = metrics;
    console.table(metrics);
  });
  requestAnimationFrame(updateConnector);
}

function recordBrowseMetrics() {
  if (state.query.trim()) return;
  const requests = state.tileTimings;
  const center = state.map.getCenter();
  const radians = Math.PI / 180;
  const features = state.map.queryRenderedFeatures({ layers: ["browse-clusters", "browse-hit-targets"] }).filter(feature => {
    if (state.map.getZoom() >= 6) return true;
    const [longitude, latitude] = feature.geometry.coordinates;
    return Math.sin(latitude * radians) * Math.sin(center.lat * radians)
      + Math.cos(latitude * radians) * Math.cos(center.lat * radians) * Math.cos((longitude - center.lng) * radians) > 0;
  });
  if (features.length && state.firstVisibleMarkersMilliseconds == null) {
    state.firstVisibleMarkersMilliseconds = performance.now();
  }
  const metrics = {
    mode: "browse", tileRequests: requests.length,
    compressedResponseBytes: requests.length ? requests.reduce((sum, entry) => sum + entry.encodedBodySize, 0) : null,
    databaseDurationMilliseconds: requests.length ? requests.reduce((sum, entry) => sum + (entry.serverTiming || []).filter(timing => timing.name === "db").reduce((total, timing) => total + timing.duration, 0), 0) : null,
    tileTransferMilliseconds: requests.reduce((sum, entry) => sum + entry.duration, 0),
    displayedItems: new Set(features.map(feature => feature.properties.uri || feature.properties.clusterID)).size,
    mapLibreReadyDurationMilliseconds: performance.now() - state.displayStartedAt,
    firstVisibleMarkersMilliseconds: state.firstVisibleMarkersMilliseconds,
    ...state.mapItemMetrics,
  };
  window.OME_GLOBE_METRICS = metrics;
}

async function selectEvent(id, fly) {
  state.selectedID = id || null;
  const selected = eventForID(id);
  if (selected && !state.query.trim() && !state.listEvents.some(event => event.uri === id)) {
    state.listEvents = [selected, ...state.listEvents.slice(0, 49)];
  }
  state.detailController?.abort();
  const cached = id ? state.detailCache.get(id) : null;
  state.selectedDetails = cached && cached.expiresAt > Date.now() ? cached.value : null;
  renderEventList();
  syncVisibleImageMarkers();

  const event = eventForID(state.selectedID);
  if (!event) {
    els.mapCard.hidden = true;
    els.connectorPath.setAttribute("d", "");
    return;
  }

  renderMapCard(event);
  if (fly && state.mapReady && event.coordinates) {
    state.skipNextMoveReload = true;
    state.map.flyTo({
      center: event.coordinates,
      zoom: Math.max(state.map.getZoom(), 2.35),
      speed: .75,
      curve: 1.25,
      essential: true,
    });
  }
  requestAnimationFrame(updateConnector);

  if (state.selectedDetails) return;
  state.detailController = new AbortController();
  try {
    const url = new URL(config.eventURL, window.location.href);
    url.searchParams.set("uri", event.uri);
    const response = await fetchJSON(url, state.detailController.signal);
    if (state.selectedID !== event.uri) return;
    state.detailCache.delete(event.uri);
    state.detailCache.set(event.uri, { value: response.value, expiresAt: Date.now() + 30000 });
    while (state.detailCache.size > 20) state.detailCache.delete(state.detailCache.keys().next().value);
    state.selectedDetails = response.value;
    renderEventList();
  } catch (error) {
    if (error.name === "AbortError") return;
    console.error("Could not load event details.", error);
    const detail = document.querySelector(`.event-card[data-id="${CSS.escape(event.uri)}"] .event-detail`);
    if (detail) detail.innerHTML = `<p class="event-detail-status">Event details could not be loaded.</p>`;
  }
}

function renderMapCard(event) {
  els.mapCard.style.setProperty("--card-color", event.color);
  const artStyle = event.image && event.imageRenderKind !== "transparent"
    ? ` style="background-image:linear-gradient(rgba(5,7,13,.15),rgba(5,7,13,.2)),url(&quot;${escapeAttribute(event.image)}&quot;)"`
    : "";
  const artContents = event.image
    ? event.imageRenderKind === "transparent"
      ? `<img src="${escapeAttribute(event.image)}" alt="">`
      : ""
    : escapeHTML(initials(event.name));
  els.mapCard.innerHTML = `
    <div class="map-card-art${event.imageRenderKind === "transparent" ? " transparent-image" : ""}"${artStyle}>${artContents}</div>
    <div class="map-card-copy">
      <h2>${escapeHTML(event.name)}</h2>
      <p><span aria-hidden="true">⌖</span> ${escapeHTML(event.locationSummary)}</p>
      <time>${escapeHTML(formatCalloutDate(event))}</time>
    </div>
    <button class="map-card-close" type="button" aria-label="Close event details">→</button>
  `;
  els.mapCard.hidden = false;
  els.mapCard.querySelector(".map-card-close").addEventListener("click", () => selectEvent(null, false));
}

function updateConnector() {
  if (!state.selectedID || !state.mapReady) {
    els.connectorPath.setAttribute("d", "");
    return;
  }
  const card = document.querySelector(`.event-card[data-id="${CSS.escape(state.selectedID)}"]`);
  const shell = document.querySelector(".discover-shell");
  const event = eventForID(state.selectedID);
  if (!card || !event?.coordinates || !shell) {
    els.connectorPath.setAttribute("d", "");
    return;
  }

  const point = state.map.project(event.coordinates);
  if (!state.mapPoints.some(point => point.uri === state.selectedID)) {
    els.connectorPath.setAttribute("d", "");
    return;
  }

  const shellRect = shell.getBoundingClientRect();
  const cardRect = card.getBoundingClientRect();
  const mapRect = document.getElementById("map").getBoundingClientRect();
  const startX = cardRect.right - shellRect.left;
  const startY = cardRect.top + cardRect.height / 2 - shellRect.top;
  const endX = mapRect.left + point.x - shellRect.left;
  const endY = mapRect.top + point.y - shellRect.top;
  const bend = Math.max(70, Math.min(170, (endX - startX) * .38));
  els.connectorPath.setAttribute(
    "d",
    `M ${startX} ${startY} C ${startX + bend} ${startY}, ${endX - bend} ${endY}, ${endX} ${endY}`,
  );
}

function distanceLabel(event) {
  const miles = eventDistance(event);
  if (!Number.isFinite(miles)) return "";
  return miles < 10 ? `${miles.toFixed(1)} mi` : `${Math.round(miles)} mi`;
}

function eventDistance(event) {
  if (!state.userLocation || !event.coordinates) return Number.POSITIVE_INFINITY;
  const [longitude1, latitude1] = state.userLocation;
  const [longitude2, latitude2] = event.coordinates;
  const toRadians = degrees => degrees * Math.PI / 180;
  const deltaLatitude = toRadians(latitude2 - latitude1);
  const deltaLongitude = toRadians(longitude2 - longitude1);
  const a = Math.sin(deltaLatitude / 2) ** 2
    + Math.cos(toRadians(latitude1)) * Math.cos(toRadians(latitude2))
    * Math.sin(deltaLongitude / 2) ** 2;
  return 3958.8 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>'"]/g, character => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character]);
}

function escapeAttribute(value = "") {
  return escapeHTML(value);
}

function escapeCSSURL(value = "") {
  return String(value).replace(/[\\"\n\r]/g, character => `\\${character}`);
}

els.searchForm.addEventListener("submit", event => {
  event.preventDefault();
  state.query = els.searchInput.value;
  state.clusterCell = null;
  state.searchBounds = null;
  state.fitSearch = true;
  window.clearTimeout(state.reloadTimer);
  loadData({ bounds: state.bounds }).catch(error => console.error(error));
});
els.searchInput.addEventListener("input", () => {
  state.query = els.searchInput.value;
  state.clusterCell = null;
  state.searchBounds = null;
  state.fitSearch = true;
  state.requestController?.abort();
  state.mapRequestController?.abort();
  state.requestID++;
  scheduleReload({ bounds: state.bounds });
});
document.querySelectorAll('input[name="catalog"]').forEach(input => {
  input.checked = state.selectedCatalogs.has(input.value);
  input.addEventListener("change", () => {
    if (input.checked) state.selectedCatalogs.add(input.value);
    else state.selectedCatalogs.delete(input.value);
    loadData({ bounds: state.bounds }).catch(error => console.error(error));
  });
});
els.jumpToNow.addEventListener("click", () => {
  state.cursor = null;
  state.clusterBrowseBounds = null;
  state.clusterCell = null;
  state.dates = "current";
  els.dateMode.value = "current";
  selectEvent(null, false);
  loadData({ bounds: state.bounds, focusNow: true }).catch(error => console.error(error));
});
els.loadMore.addEventListener("click", () => loadMoreEvents().catch(error => console.error(error)));
els.resetFilters.addEventListener("click", () => {
  state.query = "";
  state.clusterCell = null;
  state.searchBounds = null;
  state.dates = "current";
  els.dateMode.value = "current";
  els.searchInput.value = "";
  state.selectedCatalogs = new Set(config.catalogs);
  document.querySelectorAll('input[name="catalog"]').forEach(input => {
    input.checked = state.selectedCatalogs.has(input.value);
  });
  loadData({ bounds: state.bounds }).catch(error => console.error(error));
});
els.resetMapButton.addEventListener("click", () => {
  state.map?.flyTo({ center: config.initialCenter, zoom: config.initialZoom, bearing: 0, pitch: 0 });
});
els.zoomInButton.addEventListener("click", () => state.map?.zoomIn());
els.zoomOutButton.addEventListener("click", () => state.map?.zoomOut());

els.locateButton.addEventListener("click", () => {
  if (!navigator.geolocation) {
    els.dataStatus.textContent = "Location is not available in this browser";
    return;
  }
  els.dataStatus.textContent = "Finding events near you…";
  navigator.geolocation.getCurrentPosition(position => {
    state.userLocation = [position.coords.longitude, position.coords.latitude];
    els.locateButton.querySelector("span:nth-child(2)").textContent = "Near me";
    els.dataStatus.textContent = "Showing the map around your location";
    state.map?.flyTo({ center: state.userLocation, zoom: 4.2, essential: true });
  }, () => {
    els.dataStatus.textContent = "Location permission was not granted";
  });
});

window.addEventListener("resize", () => {
  state.map?.resize();
  updateConnector();
});

els.eventList.addEventListener("keydown", event => {
  if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
  const buttons = [...els.eventList.querySelectorAll(".event-card-button")];
  if (buttons.length === 0) return;
  const current = buttons.indexOf(document.activeElement);
  const index = event.key === "Home"
    ? 0
    : event.key === "End"
      ? buttons.length - 1
      : Math.max(0, Math.min(buttons.length - 1, current + (event.key === "ArrowDown" ? 1 : -1)));
  buttons[index].focus();
  event.preventDefault();
});

els.dateMode.addEventListener("change", () => {
  state.dates = els.dateMode.value;
  loadData().catch(console.error);
});
els.searchArea.addEventListener("click", () => {
  state.searchBounds = currentMapBounds();
  state.clusterCell = null;
  loadData().catch(console.error);
});
els.searchEverywhere.addEventListener("click", () => {
  state.searchBounds = null;
  state.fitSearch = true;
  loadData().catch(console.error);
});
els.previousPage.addEventListener("click", () => {
  if (!state.pageCursors.length) return;
  state.fitSearch = Boolean(state.query.trim());
  loadData({ cursor: state.pageCursors.at(-1), pageCursors: state.pageCursors.slice(0, -1) }).catch(console.error);
});
els.showPageResults.addEventListener("click", () => {
  state.highlightedMembers = null;
  els.showPageResults.hidden = true;
  renderEventList();
});
window.setInterval(() => {
  if (!document.hidden) updateBrowseTiles(true);
}, 10000);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) updateBrowseTiles(true);
});
initializeMap();
loadData({ focusNow: false }).then(() => {
  const selectedFromURL = params.get("event");
  const event = eventForID(selectedFromURL);
  if (event) {
    selectEvent(event.uri, true);
  }
}).catch(error => {
  console.error(error);
  els.dataStatus.textContent = "The calendar could not be loaded";
  els.emptyState.hidden = false;
});
