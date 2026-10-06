import Foundation
import Elementary

public struct EventViewerHTMLPage: HTMLDocument {
    public let canonicalURL: String?
    public let model: EventModel
    public let theme: EventViewerTheme
    public let feature: EventViewerFeature
    public let scheduleKind: EventViewerScheduleKind
    public let selectedStage: String?
    public let searchQuery: String?
    public let selectedContributorID: String?

    public init(
        model: EventModel,
        theme: EventViewerTheme = .ome,
        feature: EventViewerFeature = .schedule,
        scheduleKind: EventViewerScheduleKind = .singleStageAtOnce,
        selectedStage: String? = nil,
        searchQuery: String? = nil,
        selectedContributorID: String? = nil,
        canonicalURL: String? = nil
    ) {
        self.canonicalURL = canonicalURL
        self.model = model
        self.theme = theme
        self.feature = feature
        self.scheduleKind = scheduleKind
        self.selectedStage = selectedStage
        self.searchQuery = searchQuery
        self.selectedContributorID = selectedContributorID
    }

    public var title: String { model.selectedPerformance.map { $0.title + " · " + model.name } ?? model.name }
    public var lang: String { "en" }

    public var head: some HTML {
        if let canonicalURL {
            link(.rel(.canonical), .href(canonicalURL))
            meta(.custom(name: "property", value: "og:url"), .content(canonicalURL))
        }
        meta(.custom(name: "property", value: "og:title"), .content(model.name))
        if let hero = model.heroImageURL { meta(.custom(name: "property", value: "og:image"), .content(hero)) }
        meta(.name(.viewport), .content("width=device-width, initial-scale=1"))
        style {
            HTMLRaw("""
            :root {
                color-scheme: dark;
                --bg: \(theme.canvas);
                --surface: \(theme.surface);
                --panel: \(theme.raisedSurface);
                --panel-strong: #181c1f;
                --text: \(theme.ink);
                --muted: \(theme.mutedInk);
                --soft: \(theme.softInk);
                --line: \(theme.line);
                --line-soft: \(theme.lineSoft);
                --cyan: \(theme.accent);
                --green: \(theme.secondaryAccent);
                --rose: \(theme.tertiaryAccent);
                --amber: \(theme.warmAccent);
                --shadow: rgba(0, 0, 0, 0.34);
                font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }

            * { box-sizing: border-box; }
            .hidden { display: none; }
            .event-menu { display: none; position: relative; }
            .event-menu summary { cursor: pointer; padding: .6rem; }
            .event-menu .sidebar-group { position: absolute; right: 0; min-width: 14rem; padding: .8rem; background: var(--panel); border: 1px solid var(--line); box-shadow: 0 1rem 2rem var(--shadow); }

            .post-text { white-space: pre-wrap; overflow-wrap: anywhere; }
            .viewer-choices { display: flex; flex-wrap: wrap; gap: .7rem; padding: .7rem 0; }
            .viewer-choices a { padding: .4rem .7rem; border: 1px solid var(--line); border-radius: .4rem; }
            .viewer-choices .selected { color: var(--cyan); }
            .content-card img { max-height: 70vh; object-fit: contain; }

            html { background: var(--bg); scroll-behavior: smooth; }
            body {
                margin: 0;
                min-height: 100vh;
                background:
                    linear-gradient(180deg, rgba(255, 255, 255, 0.045), rgba(255, 255, 255, 0) 34rem),
                    var(--bg);
                color: var(--text);
            }
            body, a { font: inherit; }
            a { color: inherit; text-decoration-color: rgba(255, 255, 255, 0.65); text-underline-offset: .2em; }
            a:hover { text-decoration-color: var(--cyan); }
            img { max-width: 100%; }
            .page-shell { min-height: 100vh; }

            .viewer-shell {
                display: grid;
                grid-template-columns: 15.5rem minmax(0, 1fr);
                width: min(100%, 96rem);
                margin: 0 auto;
                align-items: start;
            }
            .viewer-main { min-width: 0; background: var(--bg); }
            .viewer-page-header {
                display: flex;
                align-items: center;
                min-height: 4.25rem;
                padding: .85rem 1.25rem;
                border-bottom: 1px solid rgba(255, 255, 255, .08);
                background: rgba(6, 7, 8, .72);
            }
            .viewer-page-title {
                display: inline-flex;
                align-items: center;
                gap: .7rem;
            }
            .viewer-page-title-icon {
                width: 1.35rem;
                height: 1.35rem;
                flex-basis: 1.35rem;
                color: var(--cyan);
            }
            .viewer-page-title h1 {
                margin: 0;
                max-width: none;
                font-size: clamp(1.35rem, 2.6vw, 1.8rem);
                line-height: 1.1;
                letter-spacing: 0;
            }
            .viewer-sidebar {
                position: sticky;
                top: 4.35rem;
                z-index: 4;
                display: flex;
                min-height: calc(100vh - 4.35rem);
                flex-direction: column;
                gap: 1.25rem;
                padding: 1.25rem .9rem 1.5rem;
                border-right: 1px solid rgba(255, 255, 255, .08);
                background: rgba(9, 11, 12, .94);
                backdrop-filter: blur(18px);
            }
            .sidebar-event {
                display: grid;
                grid-template-columns: 2.35rem minmax(0, 1fr);
                gap: .65rem;
                align-items: center;
                padding: .5rem .55rem .9rem;
                border-bottom: 1px solid var(--line-soft);
            }
            .sidebar-event .brand-mark { width: 2.35rem; height: 2.35rem; }
            .sidebar-event h1 { margin: 0; font-size: .9rem; line-height: 1.1; }
            .sidebar-event p { grid-column: 2; margin: -.3rem 0 0; color: var(--muted); font-size: .72rem; line-height: 1.35; }
            .sidebar-group { display: grid; gap: .25rem; }
            .sidebar-group-label { margin: .1rem .7rem .35rem; color: var(--muted); font-size: .68rem; font-weight: 900; letter-spacing: .12em; text-transform: uppercase; }
            .sidebar-link {
                display: grid;
                grid-template-columns: 1.35rem minmax(0, 1fr);
                align-items: center;
                gap: .65rem;
                min-height: 2.5rem;
                padding: .55rem .7rem;
                border: 1px solid transparent;
                border-radius: .45rem;
                color: var(--soft);
                font-size: .84rem;
                font-weight: 800;
                text-decoration: none;
            }
            .sidebar-link:hover, .sidebar-link.selected { border-color: rgba(255, 255, 255, .24); background: rgba(255, 255, 255, .1); color: var(--text); }
            .sidebar-link.selected { box-shadow: inset .2rem 0 var(--cyan); }
            .ome-symbol {
                display: block;
                width: 1.2rem;
                height: 1.2rem;
                flex: 0 0 1.2rem;
                overflow: visible;
            }
            .sidebar-link-glyph, .feature-nav-glyph { color: var(--cyan); line-height: 1; }
            .mode-icon { display: inline-grid; place-items: center; width: 1.2rem; color: var(--cyan); line-height: 1; }
            .mode-icon .ome-symbol { width: 1.15rem; height: 1.15rem; flex-basis: 1.15rem; }
            .search-result-icon { color: var(--cyan); line-height: 1; }
            .search-result-icon .ome-symbol { width: 1.2rem; height: 1.2rem; flex-basis: 1.2rem; }
            .site-header {
                position: sticky;
                top: 0;
                z-index: 5;
                border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                background: rgba(6, 7, 8, 0.82);
                backdrop-filter: blur(18px);
            }
            .nav {
                width: min(100%, 70rem);
                margin: 0 auto;
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 1rem;
                padding: .85rem 1.25rem;
            }
            .brand-link {
                display: inline-flex;
                align-items: center;
                gap: .55rem;
                color: var(--text);
                font-size: .95rem;
                font-weight: 800;
                text-decoration: none;
            }
            .brand-mark { display: block; width: 2.75rem; height: 2.75rem; object-fit: contain; }
            .brand-name {
                display: inline-block;
                background: linear-gradient(90deg, #47a9a8, #6650d3 34%, #d34f7a 68%, #d8823d);
                color: transparent;
                font-weight: 700;
                letter-spacing: .2em;
                line-height: 1;
                text-transform: uppercase;
                -webkit-background-clip: text;
                background-clip: text;
            }
            main { width: 100%; margin: 0; }
            h1, h2, h3, p { margin-top: 0; }
            .button {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                min-height: 2.9rem;
                padding: .85rem 1.05rem;
                border: 1px solid var(--line);
                background: var(--panel);
                color: var(--text);
                font-size: .95rem;
                font-weight: 800;
                text-decoration: none;
            }
            .button.primary { border-color: rgba(255, 255, 255, .72); background: var(--cyan); color: #071010; }
            .button:hover { transform: translateY(-1px); }

            .feature-nav {
                display: none;
                gap: 1.35rem;
                overflow-x: auto;
                padding: 0 1.25rem;
                border-top: 1px solid rgba(255, 255, 255, .08);
                border-bottom: 1px solid rgba(255, 255, 255, .08);
                background: rgba(13, 15, 16, .92);
            }
            .feature-nav a {
                padding: 1rem 0 .9rem;
                border-bottom: 2px solid transparent;
                color: var(--muted);
                font-size: .92rem;
                font-weight: 800;
                text-decoration: none;
                white-space: nowrap;
            }
            .feature-nav a.selected { border-bottom-color: var(--cyan); color: var(--cyan); }

            .section { border-top: 1px solid rgba(255, 255, 255, .08); background: rgba(6, 7, 8, .72); }
            .section.alt { background: rgba(13, 15, 16, .86); }
            .section-inner { padding: 1.25rem 1.25rem 3rem; }
            .section-heading {
                display: grid;
                grid-template-columns: minmax(0, .72fr) minmax(18rem, 1fr);
                gap: clamp(1.25rem, 4vw, 4rem);
                align-items: end;
                margin-bottom: 2rem;
            }
            .eyebrow {
                margin-bottom: .65rem;
                color: var(--cyan);
                font-size: .78rem;
                font-weight: 900;
                text-transform: uppercase;
            }
            h2 { margin-bottom: 0; font-size: clamp(2rem, 4vw, 3.2rem); line-height: 1.03; letter-spacing: 0; }
            .section-copy { margin-bottom: 0; color: var(--muted); font-size: 1.05rem; line-height: 1.6; }
            .schedule-heading-actions { display: grid; justify-items: end; gap: .8rem; }
            .schedule-kind-menu { position: relative; z-index: 3; }
            .mode-trigger { gap: .7rem; min-width: 12rem; justify-content: flex-start; }
            .mode-trigger-chevron { width: .55rem; height: .55rem; margin-left: auto; border-right: 1px solid var(--muted); border-bottom: 1px solid var(--muted); transform: rotate(45deg) translateY(-.12rem); }
            .schedule-kind-menu summary { list-style: none; cursor: pointer; }
            .schedule-kind-menu summary::-webkit-details-marker { display: none; }
            .mode-menu {
                position: absolute;
                top: calc(100% + .45rem);
                right: 0;
                min-width: 13rem;
                padding: .45rem;
                border: 1px solid var(--line);
                background: var(--panel-strong);
                box-shadow: 0 1rem 2.5rem var(--shadow);
            }
            .mode-menu-label { margin: .45rem .65rem .3rem; color: var(--muted); font-size: .72rem; font-weight: 900; text-transform: uppercase; }
            .mode-option {
                display: grid;
                grid-template-columns: 1.35rem minmax(0, 1fr) 1.1rem;
                align-items: center;
                gap: .55rem;
                padding: .7rem .65rem;
                color: var(--soft);
                font-size: .9rem;
                font-weight: 800;
                text-decoration: none;
            }
            .mode-option:hover, .mode-option.selected { background: rgba(255, 255, 255, .1); color: var(--text); }
            .mode-option.selected .mode-icon { color: var(--green); }
            .mode-check { color: var(--green); font-size: 1rem; text-align: right; }

            .schedule-panel { border: 1px solid var(--line-soft); background: var(--surface); box-shadow: 0 1rem 3rem var(--shadow); }
            .schedule-view { display: none; }
            .schedule-view.is-active { display: block; }
            .feature-view { display: none; }
            .feature-view.is-active { display: block; }
            .single-stage-stage-view { display: none; }
            .single-stage-stage-view.is-active { display: block; }
            .stage-selector {
                display: flex;
                gap: .75rem;
                overflow-x: auto;
                padding: .85rem 1rem;
                border-bottom: 1px solid var(--line-soft);
                background: rgba(255, 255, 255, .025);
            }
            .stage-chip {
                display: grid;
                grid-template-columns: 2.7rem auto;
                align-items: center;
                gap: .6rem;
                min-width: 9rem;
                padding: .45rem .7rem;
                border: 1px solid var(--line-soft);
                background: var(--panel);
                color: var(--soft);
                font-size: .82rem;
                font-weight: 800;
                white-space: nowrap;
            }
            .stage-chip { text-decoration: none; }
            .stage-chip:hover, .stage-chip.selected { border-color: rgba(255, 255, 255, .62); background: rgba(255, 255, 255, .1); color: var(--text); }
            .stage-chip.selected .stage-icon { box-shadow: 0 0 0 .2rem rgba(255, 255, 255, .18); }
            .stage-icon { position: relative;
                display: grid;
                place-items: center;
                width: 2.7rem;
                height: 2.7rem;
                overflow: hidden;
                border-radius: 999px;
                color: white;
                font-size: .78rem;
                font-weight: 900;
                text-align: center;
            }
            .stage-icon::after { content: ""; position: absolute; inset: 0; border-radius: inherit; background: linear-gradient(145deg, rgba(255,255,255,.16), transparent 45%, rgba(0,0,0,.18)); pointer-events: none; }
            .stage-icon img { position: absolute; z-index: 1; inset: 9%; width: 82%; height: 82%; object-fit: contain; }
            .stage-fallback { color: white; font-size: .78rem; font-weight: 900; }
            .schedule-list { display: grid; }
            .schedule-row {
                display: grid;
                grid-template-columns: 5.1rem .32rem 3.75rem minmax(0, 1fr);
                gap: 1rem;
                align-items: center;
                min-height: 5.4rem;
                padding: 1rem;
                border-bottom: 1px solid var(--line-soft);
            }
            .schedule-row:last-child { border-bottom: 0; }
            a.timeline-card, a.schedule-card, a.schedule-row { text-decoration: none; }
            .schedule-time { align-self: start; padding-top: .35rem; color: var(--cyan); font-size: .84rem; font-weight: 850; white-space: nowrap; }
            .stage-rail { align-self: stretch; min-height: 3.9rem; border-radius: 999px; }
            .schedule-row .stage-icon { width: 3.75rem; height: 3.75rem; border-radius: .35rem; }
            .schedule-copy { min-width: 0; }
            .schedule-copy h3 { margin-bottom: .3rem; color: var(--text); font-size: 1.05rem; line-height: 1.2; }
            .schedule-copy p { margin-bottom: 0; color: var(--muted); font-size: .88rem; line-height: 1.35; }
            .stage-lane { border-bottom: 1px solid var(--line-soft); }
            .stage-lane:last-child { border-bottom: 0; }
            .stage-lane-header {
                display: flex;
                align-items: center;
                gap: .75rem;
                padding: .85rem 1rem;
                border-bottom: 1px solid var(--line-soft);
                background: rgba(255, 255, 255, .025);
            }
            .stage-lane-header .stage-icon { width: 2.8rem; height: 2.8rem; }
            .stage-lane-header h3 { margin-bottom: .15rem; color: var(--text); font-size: .95rem; }
            .stage-lane-header p { margin-bottom: 0; color: var(--muted); font-size: .78rem; }
            .horizontal-schedule { min-width: 58rem; }
            .horizontal-time-header, .horizontal-stage-row { display: grid; grid-template-columns: 8rem minmax(50rem, 1fr); }
            .horizontal-time-corner { border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.025); }
            .horizontal-time-scale { position: relative; height: 2.65rem; border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.025); }
            .time-tick { position: absolute; top: .7rem; transform: translateX(-50%); color: var(--muted); font-size: .72rem; font-weight: 850; white-space: nowrap; }
            .horizontal-stage-rail { display: flex; align-items: center; gap: .65rem; padding: .65rem .75rem; border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.025); }
            .horizontal-stage-rail .stage-icon { width: 2.85rem; height: 2.85rem; }
            .horizontal-stage-rail h3 { margin-bottom: .1rem; font-size: .82rem; }
            .horizontal-stage-rail p { margin-bottom: 0; color: var(--muted); font-size: .7rem; }
            .horizontal-stage-timeline { position: relative; height: 6.8rem; border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.015); }
            .timeline-grid-line { position: absolute; top: 0; bottom: 0; width: 1px; background: rgba(255,255,255,.07); pointer-events: none; }
            .schedule-card {
                min-height: 6.8rem;
                padding: .85rem .95rem;
                border: 1px solid var(--line-soft);
                border-left-width: .3rem;
                background: var(--panel);
            }
            .schedule-card time { display: block; margin-bottom: .45rem; color: var(--cyan); font-size: .8rem; font-weight: 900; }
            .schedule-card h3 { margin-bottom: .35rem; color: var(--text); font-size: .95rem; line-height: 1.22; }
            .schedule-card p { margin-bottom: 0; color: var(--muted); font-size: .8rem; }
            .vertical-schedule { min-width: 54rem; }
            .vertical-schedule-grid { display: grid; grid-template-columns: 4.5rem repeat(3, minmax(15rem, 1fr)); }
            .single-stage-timeline { min-width: 34rem; }
            .single-stage-timeline-grid { grid-template-columns: 4.5rem minmax(24rem, 1fr); }
            .vertical-grid-corner { min-height: 7.2rem; border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.025); }
            .vertical-stage-header { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: .4rem; min-height: 7.2rem; padding: .75rem .5rem; border-left: 1px solid var(--line-soft); border-bottom: 1px solid var(--line-soft); background: rgba(255,255,255,.025); text-align: center; }
            .vertical-stage-header .stage-icon { width: 5rem; height: 5rem; border: 1px solid rgba(255,255,255,.28); }
            .vertical-stage-header h3 { margin-bottom: 0; font-size: .92rem; }
            .vertical-stage-header p { margin-bottom: 0; color: var(--muted); font-size: .72rem; }
            .vertical-time-rail, .vertical-stage-column { position: relative; min-height: 42rem; }
            .vertical-time-rail { border-right: 1px solid var(--line-soft); background: rgba(255,255,255,.015); }
            .vertical-time-label { position: absolute; right: .55rem; transform: translateY(-50%); color: var(--muted); font-size: .72rem; font-weight: 850; white-space: nowrap; }
            .vertical-stage-column { border-left: 1px solid var(--line-soft); background: rgba(255,255,255,.01); }
            .vertical-stage-column .timeline-grid-line { left: 0; right: 0; top: auto; bottom: auto; width: auto; height: 1px; }
            .timeline-card { position: absolute; z-index: 1; overflow: hidden; min-width: 0; min-height: 0; padding: .75rem .85rem; border: 1px solid rgba(255,255,255,.24); border-radius: .75rem; color: white; background: var(--stage-color); box-shadow: 0 .35rem 1rem rgba(0,0,0,.14); }
            .timeline-card::before { content: ""; position: absolute; inset: 0; background: linear-gradient(180deg, rgba(255,255,255,.12), transparent 36%, rgba(0,0,0,.16)); pointer-events: none; }
            .timeline-card > * { position: relative; z-index: 1; }
            .timeline-card h3 { margin-bottom: .45rem; color: white; font-size: 1rem; line-height: 1.12; }
            .timeline-card p { margin-bottom: 0; color: rgba(255,255,255,.85); font-size: .82rem; line-height: 1.25; }
            .timeline-card time { display: block; margin-bottom: .45rem; color: rgba(255,255,255,.86); font-size: .78rem; font-weight: 800; }
            .horizontal-timeline-card { top: .55rem; bottom: .55rem; }
            .vertical-timeline-card { left: .35rem; right: .35rem; }

            .feature-section { background: var(--bg); }
            .feature-section-inner { padding: 1.25rem 1.25rem 3rem; }
            .feature-toolbar { display: flex; align-items: center; justify-content: flex-end; gap: 1rem; margin-bottom: 1.1rem; }
            .feature-toolbar h2 { margin-bottom: .35rem; }
            .feature-toolbar p { margin-bottom: 0; color: var(--muted); line-height: 1.45; }
            .feature-search-form { display: flex; min-width: min(100%, 22rem); gap: .6rem; }
            .feature-search-input { width: 100%; min-height: 2.85rem; padding: .7rem .85rem; border: 1px solid var(--line); border-radius: .4rem; background: var(--panel); color: var(--text); outline: none; }
            .feature-search-input:focus { border-color: var(--cyan); box-shadow: 0 0 0 .2rem rgba(255, 255, 255, .12); }
            .contributor-grid { display: grid; grid-template-columns: repeat(var(--stage-count, 3), minmax(0, 1fr)); gap: .85rem; }
            .contributor-grid.profile-browse-hidden { display: none; }
            .contributor-card { display: grid; grid-template-columns: 3.5rem minmax(0, 1fr); gap: .8rem; min-height: 10.5rem; padding: 1rem; border: 1px solid var(--line-soft); border-radius: .55rem; background: var(--panel); box-shadow: 0 .8rem 2rem rgba(0,0,0,.14); }
            .contributor-card[hidden] { display: none; }
            .contributor-card-link { display: grid; grid-column: 1 / -1; grid-template-columns: 3.5rem minmax(0, 1fr); gap: .8rem; min-height: 8.4rem; color: inherit; text-decoration: none; }
            .contributor-card-link:hover h3 { color: var(--cyan); }
            .contributor-avatar { display: grid; place-items: center; width: 3.5rem; height: 3.5rem; overflow: hidden; border-radius: 999px; background: var(--contributor-color); color: white; font-size: .78rem; font-weight: 900; }
            .contributor-avatar img { width: 100%; height: 100%; object-fit: cover; }
            .contributor-card h3 { margin-bottom: .2rem; font-size: 1rem; line-height: 1.1; }
            .contributor-role { margin-bottom: .5rem; color: var(--cyan); font-size: .74rem; font-weight: 850; }
            .contributor-bio { grid-column: 1 / -1; margin-bottom: .2rem; color: var(--soft); font-size: .82rem; line-height: 1.4; }
            .contributor-handle { color: var(--muted); font-size: .75rem; }
            .contributor-appearances { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: .35rem; margin-top: auto; }
            .appearance-chip { padding: .25rem .45rem; border-radius: 999px; background: color-mix(in srgb, var(--contributor-color) 24%, transparent); color: var(--soft); font-size: .68rem; font-weight: 800; }
            .empty-search { display: none; padding: 2rem; border: 1px dashed var(--line); color: var(--muted); text-align: center; }
            .empty-search.is-visible { display: block; }
            .stage-directory { display: grid; grid-template-columns: repeat(var(--stage-count, 3), minmax(0, 1fr)); gap: .85rem; }
            .stage-directory-card { min-height: 10rem; padding: 1.1rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .stage-directory-link { display: block; color: inherit; text-decoration: none; }
            .stage-directory-link:hover h3 { color: var(--cyan); }
            .stage-directory-card .stage-icon { width: 4.5rem; height: 4.5rem; margin-bottom: .8rem; }
            .stage-directory-card h3 { margin-bottom: .25rem; font-size: 1.1rem; }
            .stage-directory-card p { margin-bottom: 0; color: var(--muted); font-size: .82rem; }
            .feature-copy { max-width: 48rem; margin-bottom: 1.6rem; color: var(--soft); line-height: 1.55; }
            .content-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .9rem; }
            .content-card { padding: 1.15rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .content-card h3 { margin-bottom: .4rem; font-size: 1rem; }
            .content-card p { margin-bottom: 0; color: var(--muted); font-size: .86rem; line-height: 1.5; }
            .content-card .card-kicker { margin-bottom: .55rem; color: var(--cyan); font-size: .72rem; font-weight: 900; letter-spacing: .08em; text-transform: uppercase; }
            .contact-list, .channel-list, .alert-list { display: grid; gap: .7rem; }
            .contact-row, .channel-row, .alert-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 1rem; align-items: center; padding: 1rem 1.1rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .channel-row-link { display: grid; grid-column: 1 / -1; grid-template-columns: minmax(0, 1fr) auto; gap: 1rem; align-items: center; color: inherit; text-decoration: none; }
            .contact-row h3, .channel-row h3, .alert-row h3 { margin-bottom: .25rem; font-size: .98rem; }
            .contact-row p, .channel-row p, .alert-row p { margin-bottom: 0; color: var(--muted); font-size: .84rem; line-height: 1.45; }
            .contact-value { color: var(--cyan); font-size: .9rem; font-weight: 800; text-align: right; }
            .channel-row { cursor: pointer; }
            .channel-row:hover { border-color: rgba(255, 255, 255, .62); background: rgba(255, 255, 255, .06); }
            .channel-meta { display: flex; flex-wrap: wrap; gap: .4rem; margin-top: .55rem; color: var(--muted); font-size: .72rem; }
            .channel-badge, .alert-badge, .setting-badge { padding: .24rem .46rem; border-radius: 999px; background: rgba(255, 255, 255, .12); color: var(--cyan); font-size: .68rem; font-weight: 900; text-transform: uppercase; letter-spacing: .06em; }
            .channel-unread { min-width: 1.65rem; padding: .22rem .4rem; border-radius: 999px; background: var(--rose); color: #190c12; font-size: .72rem; font-weight: 900; text-align: center; }
            .channel-detail { display: none; margin-top: .8rem; padding: 1.1rem; border: 1px solid var(--line-soft); background: rgba(255,255,255,.025); }
            .channel-detail.is-active { display: block; }
            .channel-detail h3 { margin-bottom: .35rem; }
            .channel-detail p { margin-bottom: 0; color: var(--soft); line-height: 1.5; }
            .location-list { display: grid; gap: 1rem; }
            .location-record { display: grid; gap: 0; overflow: hidden; border: 1px solid var(--line-soft); background: var(--panel); }
            .location-record > div:not(.location-map) { padding: 1.2rem 1.25rem 1.3rem; }
            .location-record-heading { display: block; }
            .location-record h2 { margin-bottom: .55rem; font-size: clamp(1.25rem, 2.5vw, 1.75rem); line-height: 1.1; }
            .location-address { max-width: 42rem; margin-bottom: 1rem; color: var(--soft); font-size: 1.05rem; line-height: 1.45; }
            .location-actions { display: flex; flex-wrap: wrap; gap: .65rem; }
            .location-actions .button { gap: .5rem; min-height: 2.7rem; padding: .65rem .85rem; }
            .location-actions .ome-symbol { width: 1.05rem; height: 1.05rem; flex-basis: 1.05rem; }
            .location-directions { max-width: 48rem; margin-top: 1.4rem; padding-top: 1.1rem; border-top: 1px solid var(--line-soft); }
            .location-directions p:last-child { margin-bottom: 0; color: var(--soft); line-height: 1.55; }
            .location-map { position: relative; min-height: clamp(18rem, 36vw, 30rem); overflow: hidden; border-bottom: 1px solid rgba(120,224,214,.24); background: radial-gradient(ellipse at 28% 25%, rgba(34, 124, 115, .7), transparent 32%), radial-gradient(ellipse at 72% 72%, rgba(89, 47, 157, .5), transparent 38%), linear-gradient(140deg, #122529, #075c60 50%, #181326); }
            .location-map::before { content: ""; position: absolute; inset: -12% 22% 2%; border: 1px solid rgba(176, 232, 218, .48); border-radius: 48% 52% 55% 45%; transform: rotate(-18deg); box-shadow: 0 0 0 2.5rem rgba(120,224,214,.05), 0 0 0 5rem rgba(255,255,255,.025); }
            .location-map::after { content: ""; position: absolute; inset: 0; background: linear-gradient(90deg, transparent 49.8%, rgba(255,255,255,.12) 50%, transparent 50.2%), linear-gradient(24deg, transparent 48%, rgba(255,255,255,.1) 48.2%, transparent 48.6%); opacity: .7; }
            .location-map-road { position: absolute; z-index: 1; width: 140%; height: .35rem; border-radius: 999px; background: rgba(219, 194, 224, .5); box-shadow: 0 0 0 .1rem rgba(37, 33, 74, .45); transform-origin: center; }
            .location-map-road.road-one { top: 52%; left: -18%; transform: rotate(72deg); }
            .location-map-road.road-two { top: 60%; left: -12%; transform: rotate(-14deg); background: rgba(70, 193, 188, .38); }
            .location-map-icon { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -58%); color: white; filter: drop-shadow(0 .25rem .8rem rgba(0,0,0,.4)); }
            .location-map-icon { z-index: 2; width: 3.6rem; height: 3.6rem; padding: .85rem; border-radius: 999px; background: var(--rose); color: #210d15; }
            .location-map-icon .ome-symbol { width: 2rem; height: 2rem; flex-basis: 2rem; }
            .location-map-label { position: absolute; z-index: 2; right: .8rem; bottom: .7rem; color: rgba(255,255,255,.82); font-size: .72rem; font-weight: 850; }
            .site-map-frame { position: relative; min-height: 29rem; overflow: hidden; border: 1px solid var(--line-soft); background: radial-gradient(ellipse at 30% 35%, rgba(127,74,223,.42), transparent 30%), radial-gradient(ellipse at 72% 65%, rgba(0,154,247,.35), transparent 35%), linear-gradient(145deg, #10151a, #062a2a 55%, #171026); }
            .site-map-frame::before { content: ""; position: absolute; inset: 8%; border: 1px solid rgba(255,255,255,.2); border-radius: 38% 62% 54% 46%; transform: rotate(8deg); box-shadow: inset 0 0 0 1.5rem rgba(120,224,214,.04), inset 0 0 0 3rem rgba(255,255,255,.025); }
            .site-map-frame img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; }
            .site-map-label { position: absolute; padding: .45rem .6rem; border: 1px solid rgba(255,255,255,.28); background: rgba(6,7,8,.72); color: var(--text); font-size: .72rem; font-weight: 900; letter-spacing: .05em; text-transform: uppercase; }
            .site-map-label.ursus { top: 20%; left: 21%; }
            .site-map-label.hallow { top: 43%; right: 18%; }
            .site-map-label.portal { bottom: 20%; left: 38%; }
            .site-map-label.gate { top: 12%; right: 12%; color: var(--cyan); }
            .poster-grid { display: grid; grid-template-columns: repeat(var(--stage-count, 3), minmax(0, 1fr)); gap: .9rem; }
            .poster-card { overflow: hidden; border: 1px solid var(--line-soft); background: var(--panel); }
            .poster-art { position: relative; display: grid; min-height: 18rem; place-items: end start; padding: 1rem; overflow: hidden; background: var(--poster-color); }
            .poster-art::before { content: ""; position: absolute; inset: -20% 16% 10% -12%; border: 1px solid rgba(255,255,255,.34); border-radius: 50%; transform: rotate(-24deg); box-shadow: 2rem 1rem 0 rgba(255,255,255,.06), 4rem 2rem 0 rgba(255,255,255,.04); }
            .poster-art::after { content: "OPEN MUSIC EVENT"; position: absolute; top: 1rem; left: 1rem; color: rgba(255,255,255,.66); font-size: .62rem; font-weight: 900; letter-spacing: .2em; }
            .poster-art img { display: block; width: 100%; height: auto; object-fit: contain; }
            .poster-art h3 { position: relative; z-index: 1; max-width: 10ch; color: white; font-size: 1.65rem; line-height: .98; }
            .poster-copy { padding: .85rem 1rem 1rem; }
            .poster-copy p { margin-bottom: 0; color: var(--muted); font-size: .78rem; line-height: 1.4; }
            .alert-row { align-items: start; }
            .alert-row.level-success { border-left: .3rem solid var(--green); }
            .alert-row.level-info { border-left: .3rem solid var(--cyan); }
            .alert-row.level-warning { border-left: .3rem solid var(--amber); }
            .alert-updated { color: var(--muted); font-size: .74rem; white-space: nowrap; }
            .settings-list { display: grid; gap: .7rem; max-width: 52rem; }
            .setting-row { display: flex; justify-content: space-between; align-items: center; gap: 1rem; padding: 1rem 1.1rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .setting-row h3 { margin-bottom: .25rem; font-size: .96rem; }
            .setting-row p { margin-bottom: 0; color: var(--muted); font-size: .82rem; line-height: 1.4; }
            .setting-control { width: 2.8rem; height: 1.55rem; border-radius: 999px; background: var(--cyan); box-shadow: inset 0 0 0 .18rem rgba(0,0,0,.2); }
            .setting-control::after { content: ""; display: block; width: 1.15rem; height: 1.15rem; margin: .2rem; border-radius: 999px; background: white; transform: translateX(1.1rem); }
            .workspace-banner { display: grid; grid-template-columns: auto minmax(0,1fr); gap: 1rem; align-items: start; max-width: 52rem; padding: 1.25rem; border: 1px solid rgba(255,196,115,.28); background: linear-gradient(135deg, rgba(255,196,115,.09), rgba(120,224,214,.05)); }
            .workspace-icon { display: grid; place-items: center; width: 3.1rem; height: 3.1rem; border-radius: .5rem; background: var(--amber); color: #21160a; }
            .workspace-icon .ome-symbol { width: 1.35rem; height: 1.35rem; flex-basis: 1.35rem; }
            .workspace-banner h3 { margin-bottom: .35rem; }
            .workspace-banner p { margin-bottom: 0; color: var(--soft); line-height: 1.5; }
            .search-results { display: grid; gap: .7rem; }
            .search-result { display: grid; grid-template-columns: 1.5rem minmax(0,1fr) auto; gap: .85rem; align-items: center; padding: .95rem 1rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .search-result[hidden] { display: none; }
            .search-result-link { display: block; min-width: 0; color: inherit; text-decoration: none; }
            .search-result h3 { margin-bottom: .2rem; font-size: .95rem; }
            .search-result p { margin-bottom: 0; color: var(--muted); font-size: .78rem; }
            .search-result-kind { color: var(--muted); font-size: .68rem; font-weight: 900; letter-spacing: .08em; text-transform: uppercase; }
            .contributor-profile { display: none; max-width: 54rem; }
            .contributor-profile.is-active { display: block; }
            .contributor-profile-header { display: grid; grid-template-columns: 7rem minmax(0,1fr); gap: 1.1rem; align-items: center; padding: 1.25rem; border: 1px solid var(--line-soft); background: linear-gradient(135deg, color-mix(in srgb, var(--contributor-color) 22%, var(--panel)), var(--panel)); }
            .contributor-profile .contributor-avatar { width: 7rem; height: 7rem; font-size: 1.35rem; }
            .contributor-profile h2 { margin-bottom: .3rem; }
            .contributor-profile .contributor-role { margin-bottom: .6rem; }
            .contributor-profile-body { display: grid; grid-template-columns: minmax(0, 1fr) minmax(15rem, .8fr); gap: .9rem; margin-top: .9rem; }
            .contributor-profile-body h3 { margin-bottom: .45rem; font-size: .9rem; }
            .contributor-profile-body p { margin-bottom: 0; color: var(--soft); font-size: .86rem; line-height: 1.5; }
            .profile-back { display: inline-flex; margin-bottom: .9rem; color: var(--cyan); font-size: .82rem; font-weight: 850; text-decoration: none; }
            .placeholder-panel { max-width: 46rem; padding: 1.5rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .placeholder-panel h3 { margin-bottom: .55rem; color: var(--amber); }
            .placeholder-panel p { margin-bottom: 0; color: var(--soft); line-height: 1.55; }

            .info-grid { display: grid; grid-template-columns: repeat(var(--stage-count, 3), minmax(0, 1fr)); gap: .9rem; }
            .info-summary { max-width: 48rem; margin-bottom: 1.25rem; color: var(--soft); line-height: 1.55; }
            .info-card { min-height: 8.6rem; padding: 1.25rem; border: 1px solid var(--line-soft); background: var(--panel); }
            .info-card h3 { margin-bottom: .55rem; color: var(--amber); font-size: 1.05rem; line-height: 1.2; }
            .info-card p { margin-bottom: 0; color: var(--muted); font-size: .94rem; line-height: 1.48; }
            .site-footer { display: none; }

            @media (max-width: 58rem) {
                body { padding-bottom: 5.75rem; }
                .viewer-shell { display: block; width: 100%; }
                .viewer-sidebar { display: none; }
                .event-menu { display: block; }
                .feature-nav {
                    position: fixed;
                    right: .75rem;
                    bottom: .75rem;
                    left: .75rem;
                    z-index: 6;
                    display: grid;
                    grid-template-columns: repeat(4, minmax(0, 1fr));
                    gap: .25rem;
                    padding: .3rem;
                    border: 1px solid rgba(255,255,255,.16);
                    border-radius: 1.5rem;
                    background: rgba(22, 24, 26, .88);
                    box-shadow: 0 1rem 2.5rem rgba(0,0,0,.38);
                    backdrop-filter: blur(18px);
                }
                .feature-nav a {
                    display: grid;
                    justify-items: center;
                    gap: .2rem;
                    padding: .45rem .2rem .35rem;
                    border: 0;
                    border-radius: 1.15rem;
                    font-size: .66rem;
                    line-height: 1.1;
                    text-align: center;
                }
                .feature-nav a.selected { border: 0; background: rgba(120,224,214,.16); color: var(--cyan); }
                .feature-nav .ome-symbol { width: 1.2rem; height: 1.2rem; flex-basis: 1.2rem; }
                .section-heading, .info-grid { grid-template-columns: 1fr; }
                .schedule-heading-actions { justify-items: start; }
                .stage-column-list { grid-template-columns: repeat(3, 15rem); }
                .contributor-grid, .stage-directory, .poster-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
                .contributor-profile-body { grid-template-columns: 1fr; }
            }
            @media (max-width: 40rem) {
                .site-header { position: static; }
                .nav { align-items: flex-start; flex-direction: column; }
                .button { width: 100%; }
                .mode-trigger { width: 100%; }
                .mode-menu { left: 0; right: auto; width: min(100%, 18rem); }
                .feature-toolbar { align-items: start; flex-direction: column; }
                .feature-search-form { width: 100%; }
                .contributor-grid, .stage-directory, .poster-grid, .content-grid { grid-template-columns: 1fr; }
                .contact-row, .channel-row, .alert-row { grid-template-columns: 1fr; }
                .contact-value, .alert-updated { text-align: left; }
                .contributor-profile-header { grid-template-columns: 4.75rem minmax(0,1fr); }
                .contributor-profile .contributor-avatar { width: 4.75rem; height: 4.75rem; }
                .schedule-row { grid-template-columns: 4.6rem .25rem 3.25rem minmax(0, 1fr); gap: .7rem; padding-inline: .75rem; }
                .schedule-row .stage-icon { width: 3.25rem; height: 3.25rem; }
                .horizontal-schedule { min-width: 46rem; }
                .vertical-schedule { min-width: 48rem; }
                .vertical-schedule-grid { grid-template-columns: 3.9rem repeat(var(--stage-count, 3), minmax(13rem, 1fr)); }
                .viewer-page-header { min-height: 3.75rem; padding-inline: 1rem; }
                .location-map { min-height: 17rem; }
            }
            """)
        }
    }

    public var body: some HTML {
        div(.class("page-shell")) {
            EventViewerIconSprite()
            EventViewerSiteHeader(theme: theme, eventName: model.name, feature: feature)
            div(.class("viewer-shell")) {
                EventViewerSidebar(
                    model: model,
                    theme: theme,
                    feature: feature
                )
                div(.class("viewer-main")) {
                    main {
                        EventViewerPageHeader(feature: feature)
                        EventViewerFeatureNavigation(feature: feature)
                        EventViewerFeatureViews(
                            model: model,
                            theme: theme,
                            feature: feature,
                            scheduleKind: scheduleKind,
                            selectedStage: selectedStage,
                            searchQuery: searchQuery,
                            selectedContributorID: selectedContributorID
                        )
                    }
                }
            }

        }
    }
}

struct EventViewerSiteHeader: HTML {
    let theme: EventViewerTheme
    let eventName: String
    let feature: EventViewerFeature

    var body: some HTML {
        header(.class("site-header")) {
            nav(.class("nav")) {
                a(.class("brand-link"), .href("#top")) {
                    img(.class("brand-mark"), .src(theme.brandMarkURL), .alt(""))
                    span(.class("brand-name")) { theme.productName }
                }
                details(.class("event-menu")) {
                    summary { eventName }
                    EventViewerSidebarGroup(label: "Event", features: EventViewerFeature.event.filter { $0 != .notifications } + [.about], selectedFeature: feature)
                }
            }
        }
    }
}

struct EventViewerSidebar: HTML {
    let model: EventModel
    let theme: EventViewerTheme
    let feature: EventViewerFeature

    var body: some HTML {
        aside(.class("viewer-sidebar"), .id("viewer-sidebar")) {
            a(.class("sidebar-event"), .href("#top")) {
                img(.class("brand-mark"), .src(theme.brandMarkURL), .alt(""))
                div {
                    h1 { model.name }
                }
                p { model.location }
            }
            nav(.class("sidebar-navigation")) {
                EventViewerSidebarGroup(
                    label: "Explore",
                    features: EventViewerFeature.primary,
                    selectedFeature: feature
                )
                EventViewerSidebarGroup(
                    label: "Event",
                    features: EventViewerFeature.event.filter { $0 != .notifications },
                    selectedFeature: feature
                )
                EventViewerSidebarGroup(
                    label: "Information",
                    features: [.about],
                    selectedFeature: feature
                )
            }
        }
    }
}

struct EventViewerSidebarGroup: HTML {
    let label: String
    let features: [EventViewerFeature]
    let selectedFeature: EventViewerFeature

    var body: some HTML {
        div(.class("sidebar-group")) {
            p(.class("sidebar-group-label")) { label }
            for feature in features {
                EventViewerFeatureLink(
                    feature: feature,
                    selectedFeature: selectedFeature,
                    style: .sidebar
                )
            }
        }
    }
}

struct EventViewerFeatureLink: HTML {
    enum Style: Equatable {
        case sidebar
        case mobile
    }

    let feature: EventViewerFeature
    let selectedFeature: EventViewerFeature
    let style: Style

    var body: some HTML {
        a(
            .class([
                style == .sidebar ? "sidebar-link" : "feature-nav-link",
                feature == selectedFeature ? "selected" : ""
            ]),
            .href("?feature=\(feature.webValue)#viewer"),
            .data("feature", value: feature.webValue)
        ) {
            EventViewerSymbol(
                icon: feature.icon,
                style: style == .sidebar ? "sidebar-link-glyph" : "feature-nav-glyph"
            )
            span { feature.title }
        }
    }
}

struct EventViewerPageHeader: HTML {
    let feature: EventViewerFeature

    var body: some HTML {
        header(.class("viewer-page-header"), .data("feature-page-header", value: "true")) {
            div(.class("viewer-page-title")) {
                EventViewerSymbol(icon: feature.icon, style: "viewer-page-title-icon")
                h1 { feature.title }
            }
        }
    }
}

extension EventViewerIcon {
    var webIconName: String {
        switch self {
        case .schedule:
            return "calendar"
        case .contributors:
            return "users-round"
        case .stages:
            return "grid-2x2"
        case .communications:
            return "megaphone"
        case .contactInfo:
            return "phone"
        case .location:
            return "map-pin"
        case .siteMap:
            return "map"
        case .posters:
            return "images"
        case .notifications:
            return "bell"
        case .settings:
            return "settings"
        case .workspace:
            return "archive"
        case .search:
            return "search"
        case .about:
            return "info"
        case .contributor:
            return "user"
        case .performance:
            return "mic-vocal"
        case .scheduleSingleStage:
            return "calendar-clock"
        case .scheduleManyHorizontal:
            return "columns-2"
        case .scheduleManyVertical:
            return "columns-3"
        case .list:
            return "list"
        }
    }

    var webSymbolID: String {
        "lucide-\(webIconName)"
    }

    var webSVGBody: String {
        switch self {
        case .schedule:
            return """
            <path d='M8 2v4' />
            <path d='M16 2v4' />
            <rect width='18' height='18' x='3' y='4' rx='2' />
            <path d='M3 10h18' />
            """
        case .contributors:
            return """
            <path d='M18 21a8 8 0 0 0-16 0' />
            <circle cx='10' cy='8' r='5' />
            <path d='M22 20c0-3.37-2-6.5-4-8a5 5 0 0 0-.45-8.3' />
            """
        case .stages:
            return """
            <path d='M12 3v18' />
            <path d='M3 12h18' />
            <rect x='3' y='3' width='18' height='18' rx='2' />
            """
        case .communications:
            return """
            <path d='m3 11 18-5v12L3 14v-3z' />
            <path d='M11.6 16.8a3 3 0 1 1-5.8-1.6' />
            """
        case .contactInfo:
            return """
            <path d='M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z' />
            """
        case .location:
            return """
            <path d='M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0' />
            <circle cx='12' cy='10' r='3' />
            """
        case .siteMap:
            return """
            <path d='M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z' />
            <path d='M15 5.764v15' />
            <path d='M9 3.236v15' />
            """
        case .posters:
            return """
            <path d='M18 22H4a2 2 0 0 1-2-2V6' />
            <path d='m22 13-1.296-1.296a2.41 2.41 0 0 0-3.408 0L11 18' />
            <circle cx='12' cy='8' r='2' />
            <rect width='16' height='16' x='6' y='2' rx='2' />
            """
        case .notifications:
            return """
            <path d='M10.268 21a2 2 0 0 0 3.464 0' />
            <path d='M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326' />
            """
        case .settings:
            return """
            <path d='M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z' />
            <circle cx='12' cy='12' r='3' />
            """
        case .workspace:
            return """
            <rect width='20' height='5' x='2' y='3' rx='1' />
            <path d='M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8' />
            <path d='M10 12h4' />
            """
        case .search:
            return """
            <circle cx='11' cy='11' r='8' />
            <path d='m21 21-4.3-4.3' />
            """
        case .about:
            return """
            <circle cx='12' cy='12' r='10' />
            <path d='M12 16v-4' />
            <path d='M12 8h.01' />
            """
        case .contributor:
            return """
            <path d='M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2' />
            <circle cx='12' cy='7' r='4' />
            """
        case .performance:
            return """
            <path d='m11 7.601-5.994 8.19a1 1 0 0 0 .1 1.298l.817.818a1 1 0 0 0 1.314.087L15.09 12' />
            <path d='M16.5 21.174C15.5 20.5 14.372 20 13 20c-2.058 0-3.928 2.356-6 2-2.072-.356-2.775-3.369-1.5-4.5' />
            <circle cx='16' cy='7' r='5' />
            """
        case .scheduleSingleStage:
            return """
            <path d='M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5' />
            <path d='M16 2v4' />
            <path d='M8 2v4' />
            <path d='M3 10h5' />
            <path d='m17.5 17.5-1.5-1.2V14' />
            <circle cx='16' cy='16' r='6' />
            """
        case .scheduleManyHorizontal:
            return """
            <rect width='18' height='18' x='3' y='3' rx='2' />
            <path d='M12 3v18' />
            """
        case .scheduleManyVertical:
            return """
            <rect width='18' height='18' x='3' y='3' rx='2' />
            <path d='M9 3v18' />
            <path d='M15 3v18' />
            """
        case .list:
            return """
            <path d='M3 12h.01' />
            <path d='M3 18h.01' />
            <path d='M3 6h.01' />
            <path d='M8 12h13' />
            <path d='M8 18h13' />
            <path d='M8 6h13' />
            """
        }
    }
}

struct EventViewerIconSprite: HTML {
    var body: some HTML {
        let symbols = EventViewerIcon.allCases.map { icon in
            "<symbol id='\(icon.webSymbolID)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>\(icon.webSVGBody)</symbol>"
        }.joined()

        HTMLRaw("""
        <!-- Lucide Icons v0.577.0, ISC License. -->
        <svg class='icon-sprite' aria-hidden='true'>\(symbols)</svg>
        """)
    }
}

struct EventViewerSymbol: HTML {
    let icon: EventViewerIcon
    let style: String?

    init(icon: EventViewerIcon, style: String? = nil) {
        self.icon = icon
        self.style = style
    }

    var body: some HTML {
        HTMLRaw("""
        <svg class='ome-symbol ome-symbol-\(icon.rawValue) lucide lucide-\(icon.webIconName) \(style ?? "")' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' data-icon='\(icon.rawValue)' data-icon-set='lucide' aria-hidden='true' focusable='false'>
            <use href='#\(icon.webSymbolID)'></use>
        </svg>
        """)
    }
}

struct EventViewerFeatureNavigation: HTML {
    let feature: EventViewerFeature

    var body: some HTML {
        nav(.class("feature-nav")) {
            for item in EventViewerFeature.primary {
                EventViewerFeatureLink(
                    feature: item,
                    selectedFeature: feature,
                    style: .mobile
                )
            }
        }
    }
}

struct EventViewerFeatureViews: HTML {
    let model: EventModel
    let theme: EventViewerTheme
    let feature: EventViewerFeature
    let scheduleKind: EventViewerScheduleKind
    let selectedStage: String?
    let searchQuery: String?
    let selectedContributorID: String?

    var body: some HTML {
        div(.class("feature-views"), .id("viewer")) {
            div(.class("feature-view is-active")) {
                if let performance = model.selectedPerformance {
                    EventViewerPerformanceDetail(performance: performance, timeZone: model.timeZoneIdentifier)
                } else {
                switch feature {
                case .schedule:
                    EventViewerSchedule(model: model, theme: theme, scheduleKind: scheduleKind, selectedStage: selectedStage)
                case .contributors:
                    EventViewerContributorDirectory(model: model, theme: theme, identifier: "contributors", searchQuery: searchQuery, selectedContributorID: selectedContributorID)
                case .stages: EventViewerStageDirectory(model: model, theme: theme)
                case .search: EventViewerSearchDirectory(model: model, theme: theme, searchQuery: searchQuery)
                case .communications: EventViewerCommunications(model: model)
                case .contactInfo: EventViewerContactInfo(model: model)
                case .location: EventViewerLocation(model: model)
                case .siteMap: EventViewerSiteMap(model: model)
                case .posters: EventViewerPosters(model: model)
                default: EventViewerInfo(model: model)
                }
                }
            }
        }
    }
}

struct EventViewerContributorDirectory: HTML {
    let model: EventModel
    let theme: EventViewerTheme
    let identifier: String
    let searchQuery: String?
    let selectedContributorID: String?

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                div(.class("feature-toolbar")) {
                    form(.class("feature-search-form"), .method(.get)) {
                        input(.type(.hidden), .name("feature"), .value("contributors"))
                        input(
                            .class("feature-search-input"),
                            .id("contributor-search-\(identifier)"),
                            .type(.search),
                            .name("q"),
                            .placeholder("Search contributor profiles"),
                            .value(searchQuery ?? "")
                        )
                    }
                }
                div(.class(selectedContributorID == nil ? "contributor-grid" : "hidden"), .id("contributor-results-\(identifier)")) {
                    for contributor in model.contributors.filter({ (searchQuery ?? "").isEmpty || $0.searchText.localizedCaseInsensitiveContains(searchQuery ?? "") }) {
                        EventViewerContributorCard(
                            contributor: contributor,
                            performances: model.performances,
                            theme: theme
                        )
                    }
                }
                for contributor in model.contributors.filter({ $0.id == selectedContributorID }) {
                    EventViewerContributorProfile(
                        contributor: contributor,
                        performances: model.schedulePerformances,
                        theme: theme,
                        isActive: contributor.id == selectedContributorID
                    )
                }
                p(.class("empty-search"), .style(model.contributors.contains { (searchQuery ?? "").isEmpty || $0.searchText.localizedCaseInsensitiveContains(searchQuery ?? "") } ? "display:none" : "display:block"), .id("contributor-empty-\(identifier)")) {
                    "No contributor profiles match that search."
                }
            }
        }
    }
}

struct EventViewerContributorCard: HTML {
    let contributor: Contributor
    let performances: [Performance]
    let theme: EventViewerTheme

    var body: some HTML {
        article(
            .class("contributor-card"),
            .data("search", value: contributor.searchText),
            .style("--contributor-color: \(contributor.accentColor)")
        ) {
            a(
                .class("contributor-card-link"),
                .href("?feature=contributors&contributor=\(contributor.id)#viewer"),
                .data("contributor", value: contributor.id)
            ) {
                div(.class("contributor-avatar")) {
                    if let avatarURL = contributor.avatarURL {
                        img(.src(avatarURL), .alt(contributor.name))
                    } else {
                        span { contributor.initials }
                    }
                }
                div {
                    h3 { contributor.name }
                    p(.class("contributor-role")) { contributor.role }
                    if let handle = contributor.handle {
                        p(.class("contributor-handle")) { handle }
                    }
                }
                p(.class("contributor-bio")) { contributor.bio }
                div(.class("contributor-appearances")) {
                    for performanceID in contributor.performanceIDs {
                        if let performance = performances.first(where: { $0.id == performanceID }) {
                            span(.class("appearance-chip")) {
                                "\(performance.title) · \(performance.time)"
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerContributorProfile: HTML {
    let contributor: Contributor
    let performances: [Performance]
    let theme: EventViewerTheme
    let isActive: Bool

    var body: some HTML {
        section(
            .class(["contributor-profile", isActive ? "is-active" : ""]),
            .id("contributor-profile-\(contributor.id)"),
            .data("profile", value: contributor.id),
            .style("--contributor-color: \(contributor.accentColor)")
        ) {
            a(
                .class("profile-back"),
                .href("?feature=contributors#viewer"),
                .data("profile-back", value: "true")
            ) { "← All contributors" }
            div(.class("contributor-profile-header")) {
                div(.class("contributor-avatar")) {
                    if let avatarURL = contributor.avatarURL {
                        img(.src(avatarURL), .alt(contributor.name))
                    } else {
                        span { contributor.initials }
                    }
                }
                div {
                    p(.class("eyebrow")) { contributor.role }
                    h2 { contributor.name }
                    if let handle = contributor.handle {
                        p(.class("contributor-handle")) { handle }
                    }
                }
            }
            div(.class("contributor-profile-body")) {
                div(.class("content-card")) {
                    h3 { "About" }
                    p { contributor.bio }
                    for link in contributor.links { a(.href(link.href ?? "")) { link.label } }

                }
                div(.class("content-card")) {
                    h3 { "Appearances" }
                    if appearances.isEmpty {
                        p { "No schedule appearances are attached to this profile yet." }
                    } else {
                        div(.class("contributor-appearances")) {
                            for performance in appearances {
                                a(
                                    .class("appearance-chip"),
                                    .href(performance.detailURL),
                                    .data("feature", value: EventViewerFeature.schedule.webValue),
                                    .data("schedule-stage", value: performance.stageID)
                                ) {
                                    "\(performance.title) · \(performance.time)"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    var appearances: [Performance] {
        contributor.performanceIDs.compactMap { id in
            performances.first(where: { $0.id == id })
        }
    }
}

struct EventViewerSearchDirectory: HTML {
    let model: EventModel
    let theme: EventViewerTheme
    let searchQuery: String?

    var hasResults: Bool {
        let query = searchQuery ?? ""
        return model.contributors.contains { $0.searchText.localizedCaseInsensitiveContains(query) }
            || model.performances.contains { $0.searchText.localizedCaseInsensitiveContains(query) }
            || model.stagePerformances.contains { $0.stage.localizedCaseInsensitiveContains(query) }
    }

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                div(.class("feature-toolbar")) {
                    form(.class("feature-search-form"), .method(.get)) {
                        input(.type(.hidden), .name("feature"), .value("search"))
                        input(
                            .class("feature-search-input"),
                            .id("event-search"),
                            .type(.search),
                            .name("q"),
                            .placeholder("Search the event"),
                            .value(searchQuery ?? "")
                        )
                    }
                }
                div(.class("search-results"), .id("event-search-results")) {
                    for contributor in model.contributors.filter({ (searchQuery ?? "").isEmpty || $0.searchText.localizedCaseInsensitiveContains(searchQuery ?? "") }) {
                        article(
                            .class("search-result"),
                            .data("search", value: contributor.searchText),
                            .data("result-type", value: "contributor")
                        ) {
                            EventViewerSymbol(icon: .contributor, style: "search-result-icon")
                            a(
                                .class("search-result-link"),
                                .href("?feature=contributors&contributor=\(contributor.id)#viewer"),
                                .data("feature", value: EventViewerFeature.contributors.webValue),
                                .data("contributor", value: contributor.id)
                            ) {
                                h3 { contributor.name }
                                p { "\(contributor.role) · \(contributor.bio)" }
                            }
                            span(.class("search-result-kind")) { "Profile" }
                        }
                    }
                    for performance in model.performances.filter({ (searchQuery ?? "").isEmpty || $0.searchText.localizedCaseInsensitiveContains(searchQuery ?? "") }) {
                        article(
                            .class("search-result"),
                            .data("search", value: [performance.title, performance.stage, performance.time].joined(separator: " ").lowercased()),
                            .data("result-type", value: "performance")
                        ) {
                            EventViewerSymbol(icon: .performance, style: "search-result-icon")
                            a(
                                .class("search-result-link"),
                                .href(performance.detailURL),
                                .data("feature", value: EventViewerFeature.schedule.webValue),
                                .data("schedule-stage", value: performance.stageID)
                            ) {
                                h3 { performance.title }
                                p { "\(performance.stage) · \(performance.timeRangeText)" }
                            }
                            span(.class("search-result-kind")) { "Performance" }
                        }
                    }
                    for stage in model.stagePerformances.filter({ (searchQuery ?? "").isEmpty || $0.stage.localizedCaseInsensitiveContains(searchQuery ?? "") }) {
                        article(
                            .class("search-result"),
                            .data("search", value: stage.stage.lowercased()),
                            .data("result-type", value: "stage")
                        ) {
                            EventViewerSymbol(icon: .stages, style: "search-result-icon")
                            a(
                                .class("search-result-link"),
                                .href("?feature=stages#viewer"),
                                .data("feature", value: EventViewerFeature.stages.webValue)
                            ) {
                                h3 { stage.stage }
                                p { "Stage with " + String(model.performances.filter { $0.stageID == stage.stageID }.count) + " performances" }
                            }
                            span(.class("search-result-kind")) { "Stage" }
                        }
                    }
                }
                p(.class("empty-search"), .style(hasResults ? "display:none" : "display:block"), .id("event-search-empty")) {
                    "Nothing in the event matches that search."
                }
            }
        }
    }
}

struct EventViewerStageDirectory: HTML {
    let model: EventModel
    let theme: EventViewerTheme

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                div(.class("stage-directory")) {
                    for stage in stages {
                        let stagePerformances = model.performances.filter { $0.stageID == stage.stageID }
                        article(.class("stage-directory-card")) {
                            a(
                                .class("stage-directory-link"),
                                .href(stage.scheduleURL),
                                .data("feature", value: EventViewerFeature.schedule.webValue),
                                .data("schedule-stage", value: stage.stageID)
                            ) {
                                EventViewerStageIcon(performance: stage, fallbackColor: theme.accent)
                                h3 { stage.stage }
                                p { "\(stagePerformances.count) performances · \(timeRangeText(for: stagePerformances))" }
                            }
                        }
                    }
                }
            }
        }
    }

    var stages: [Performance] {
        model.stagePerformances
    }

    func timeRangeText(for performances: [Performance]) -> String {
        let metrics = EventViewerTimelineMetrics(performances: performances)
        return "\(EventViewerTimelineMetrics.hourLabel(for: metrics.startMinute)) – \(EventViewerTimelineMetrics.hourLabel(for: metrics.endMinute))"
    }
}

struct EventViewerCommunications: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                EventViewerChoices(title: "Channels", choices: model.categoryChoices)
                if model.posts.isEmpty { p { "No posts published for this selection." } }
                for post in model.posts {
                    article(.class("content-card")) {
                        if post.pinned { p(.class("eyebrow")) { "Pinned" } }
                        h2 { a(.href(post.url)) { post.title } }
                        p { post.date }
                        p(.class("post-text")) {
                            for run in post.text {
                                if let url = run.url { a(.href(url)) { run.text } }
                                else { span { run.text } }
                            }
                        }
                        for image in post.images {
                            if let url = image.imageURL { img(.src(url), .alt(image.title)) }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerContactInfo: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                if model.contacts.isEmpty { p { "No contact links published." } }
                div(.class("contact-list")) {
                    for contact in model.contacts {
                        article(.class("contact-row")) {
                            div {
                                h3 { contact.label }
                                if let detail = contact.detail {
                                    p { detail }
                                }
                            }
                            if let href = contact.href {
                                a(.class("contact-value"), .href(href)) { contact.value }
                            } else {
                                span(.class("contact-value")) { contact.value }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerLocation: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                if model.locations.isEmpty { p { "No locations published." } }
                div(.class("location-list")) {
                    for (index, location) in model.locations.enumerated() {
                        article(.class("location-record")) {
                            div {
                                div(.class("location-record-heading")) {
                                    if model.locations.count > 1 {
                                        p(.class("card-kicker")) { "Location \(index + 1)" }
                                    }
                                    h2 { location.name }
                                }
                                p(.class("location-address")) { location.address }
                                div(.class("location-actions")) {
                                    a(.class(["button", "primary"]), .href(location.appleMapsURL)) {
                                        EventViewerSymbol(icon: .location)
                                        span { "Open in Maps" }
                                    }
                                    a(.class("button"), .href(location.googleMapsURL)) {
                                        EventViewerSymbol(icon: .siteMap)
                                        span { "Google Maps" }
                                    }
                                }
                                if let detail = location.detail {
                                    div(.class("location-directions")) {
                                        p(.class("card-kicker")) { "Directions" }
                                        p { detail }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerSiteMap: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                EventViewerChoices(title: "Map", choices: model.mapChoices)
                div(.class("site-map-frame")) {
                    if let siteMapURL = model.siteMapURL {
                        img(.src(siteMapURL), .alt("Site map for " + model.name))
                    } else { p { "No site map published." } }
                }
            }
        }
    }
}

struct EventViewerPosters: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                if model.posters.isEmpty { p { "No posters published." } }
                div(.class("poster-grid")) {
                    for poster in model.posters {
                        article(.class("poster-card")) {
                            div(.class("poster-art"), .style("--poster-color: " + poster.accentColor)) {
                                if let imageURL = poster.imageURL {
                                    img(.src(imageURL), .alt(poster.title))
                                }
                                h3 { poster.title }
                            }
                            div(.class("poster-copy")) {
                                if let subtitle = poster.subtitle {
                                    p { subtitle }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerSchedule: HTML {
    let model: EventModel
    let theme: EventViewerTheme
    let scheduleKind: EventViewerScheduleKind
    let selectedStage: String?

    var body: some HTML {
        section(.class("section"), .id("schedule")) {
            div(.class("section-inner")) {
                div(.class("section-heading")) {
                    div {
                        h2 { model.scheduleLabel ?? "Schedule" }
                    }
                    div(.class("schedule-heading-actions")) {
                        EventViewerScheduleKindMenu(scheduleKind: scheduleKind, context: model.scheduleQuery)
                    }
                }

                EventViewerChoices(title: "Program", choices: model.programChoices)
                EventViewerChoices(title: "Day", choices: model.dayChoices)
                if model.schedulePerformances.isEmpty { p { "No timed items published for this selection." } }
                div(.class("schedule-panel")) {
                    EventViewerSingleStageSchedule(
                        stages: model.scheduleStages,
                        performances: model.schedulePerformances,
                        theme: theme,
                        isActive: scheduleKind == .singleStageAtOnce,
                        selectedStage: selectedStage
                    )
                    EventViewerManyStagesHorizontalSchedule(
                        stages: model.scheduleStages,
                        performances: model.schedulePerformances,
                        theme: theme,
                        isActive: scheduleKind == .allStagesAtOnceHorizontal
                    )
                    EventViewerManyStagesVerticalSchedule(
                        stages: model.scheduleStages,
                        performances: model.schedulePerformances,
                        theme: theme,
                        isActive: scheduleKind == .allStagesAtOnceVertical
                    )
                    EventViewerListSchedule(
                        performances: model.schedulePerformances.sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) },
                        theme: theme,
                        isActive: scheduleKind == .list
                    )
                }
            }
        }
    }
}

struct EventViewerScheduleKindMenu: HTML {
    let scheduleKind: EventViewerScheduleKind
    let context: String

    var body: some HTML {
        details(.class("schedule-kind-menu")) {
            summary(.class(["button", "mode-trigger"])) {
                span(.class("mode-icon")) {
                    EventViewerSymbol(icon: scheduleKind.icon)
                }
                span(.class("mode-trigger-label")) { "View: \(scheduleKind.title)" }
                span(.class("mode-trigger-chevron")) { "" }
            }
            div(.class("mode-menu")) {
                p(.class("mode-menu-label")) { "Mode" }
                for kind in EventViewerScheduleKind.allCases {
                    let classes = kind == scheduleKind
                        ? ["mode-option", "selected"]
                        : ["mode-option"]
                    a(
                        .class(classes),
                        .href("?\(context)&schedule-kind=\(kind.webValue)#schedule")
                    ) {
                        span(.class("mode-icon")) {
                            EventViewerSymbol(icon: kind.icon)
                        }
                        span { kind.title }
                        span(.class("mode-check")) {
                            if kind == scheduleKind { "✓" }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerSingleStageSchedule: HTML {
    let stages: [Performance]
    let performances: [Performance]
    let theme: EventViewerTheme
    let isActive: Bool
    let selectedStage: String?

    var body: some HTML {
        div(
            .class([
                "schedule-view",
                "single-stage-view",
                isActive ? "is-active" : ""
            ]),
            .id("schedule-view-single-stage")
        ) {
            EventViewerStageSelector(
                performances: stages,
                theme: theme,
                selectedStage: selectedStage
            )
            for stage in stages {
                let stageValue = stage.stageID
                div(
                    .class([
                        "single-stage-stage-view",
                        resolvedSelectedStage == stageValue ? "is-active" : ""
                    ]),
                    .id("single-stage-\(stageValue)"),
                    .data("stage", value: stageValue)
                ) {
                    EventViewerSingleStageTimeline(
                        stage: stage,
                        performances: performances.filter { $0.stageID == stage.stageID },
                        timelinePerformances: performances,
                        theme: theme
                    )
                }
            }
        }
    }


    var resolvedSelectedStage: String? {
        let availableStages = stages.map { $0.stageID }
        if let selectedStage, availableStages.contains(selectedStage) {
            return selectedStage
        }
        return availableStages.first
    }
}

struct EventViewerSingleStageTimeline: HTML {
    let stage: Performance
    let performances: [Performance]
    let timelinePerformances: [Performance]
    let theme: EventViewerTheme

    var body: some HTML {
        let metrics = EventViewerTimelineMetrics(performances: timelinePerformances)

        div(.class("single-stage-timeline")) {
            div(
                .class(["vertical-schedule-grid", "single-stage-timeline-grid"])
            ) {
                div(.class("vertical-grid-corner")) {}
                div(.class("vertical-stage-header")) {
                    EventViewerStageIcon(
                        performance: stage,
                        fallbackColor: theme.accent,
                        showsStageColorBackground: true
                    )
                    h3 { stage.stage }
                }

                div(
                    .class("vertical-time-rail"),
                    .style("height: \(metrics.timelineHeight)px")
                ) {
                    for hour in metrics.hours {
                        span(
                            .class("vertical-time-label"),
                            .style("top: \(metrics.position(for: hour) * 100)%")
                        ) {
                            EventViewerTimelineMetrics.hourLabel(for: hour)
                        }
                    }
                }

                div(
                    .class("vertical-stage-column"),
                    .style("height: \(metrics.timelineHeight)px")
                ) {
                    for hour in metrics.hours {
                        div(
                            .class("timeline-grid-line"),
                            .style("top: \(metrics.position(for: hour) * 100)%")
                        ) {}
                    }
                    for performance in performances {
                        EventViewerTimelineCard(
                            performance: performance,
                            theme: theme,
                            metrics: metrics,
                            orientation: .vertical
                        )
                    }
                }
            }
        }
    }
}

struct EventViewerManyStagesHorizontalSchedule: HTML {
    let stages: [Performance]
    let performances: [Performance]
    let theme: EventViewerTheme
    let isActive: Bool

    var body: some HTML {
        div(
            .class([
                "schedule-view",
                "many-stages-view",
                "many-horizontal-view",
                isActive ? "is-active" : ""
            ]),
            .id("schedule-view-many-horizontal")
        ) {
            EventViewerHorizontalSchedule(
                stages: stages,
                performances: performances,
                theme: theme
            )
        }
    }

}

struct EventViewerManyStagesVerticalSchedule: HTML {
    let stages: [Performance]
    let performances: [Performance]
    let theme: EventViewerTheme
    let isActive: Bool

    var body: some HTML {
        div(
            .class([
                "schedule-view",
                "many-stages-view",
                "many-vertical-view",
                isActive ? "is-active" : ""
            ]),
            .id("schedule-view-many-vertical")
        ) {
            EventViewerVerticalSchedule(
                stages: stages,
                performances: performances,
                theme: theme
            )
        }
    }

}

struct EventViewerTimelineMetrics: Sendable {
    let startMinute: Int
    let endMinute: Int
    let pointsPerHour: Int = 96

    init(performances: [Performance]) {
        let rawStart = performances.compactMap(\.startMinute).min() ?? 0
        let rawEnd = performances.compactMap(\.endMinute).max() ?? rawStart + 60
        let alignedStart = (rawStart / 60) * 60
        let alignedEnd = ((rawEnd + 59) / 60) * 60
        self.startMinute = alignedStart
        self.endMinute = max(alignedStart + 60, alignedEnd)
    }

    var duration: Int { endMinute - startMinute }
    var timelineHeight: Int { duration * pointsPerHour / 60 }
    var hours: [Int] { Array(stride(from: startMinute, through: endMinute, by: 60)) }

    func position(for minute: Int) -> Double {
        Double(max(0, min(duration, minute - startMinute))) / Double(duration)
    }

    func width(for performance: Performance) -> Double {
        let start = performance.startMinute ?? startMinute
        let end = performance.endMinute ?? start + 60
        return position(for: end) - position(for: start)
    }

    static func hourLabel(for minute: Int) -> String {
        let hour = (minute / 60) % 24
        let normalizedHour = hour == 0 || hour == 12 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return "\(normalizedHour):00 \(suffix)"
    }
}

struct EventViewerHorizontalSchedule: HTML {
    let stages: [Performance]
    let performances: [Performance]
    let theme: EventViewerTheme

    var body: some HTML {
        let metrics = EventViewerTimelineMetrics(performances: performances)

        div(.class("horizontal-schedule")) {
                div(.class("horizontal-time-header")) {
                    div(.class("horizontal-time-corner")) {}
                    div(.class("horizontal-time-scale")) {
                        for hour in metrics.hours {
                            span(
                                .class("time-tick"),
                                .style("left: \(metrics.position(for: hour) * 100)%")
                            ) {
                                EventViewerTimelineMetrics.hourLabel(for: hour)
                            }
                        }
                    }
                }

                for stage in stages {
                    let stagePerformances = performances.filter { $0.stageID == stage.stageID }
                    div(.class("horizontal-stage-row")) {
                        div(.class("horizontal-stage-rail")) {
                            EventViewerStageIcon(performance: stage, fallbackColor: theme.accent)
                            div {
                                h3 { stage.stage }
                            }
                        }
                        div(.class("horizontal-stage-timeline")) {
                            for hour in metrics.hours {
                                div(
                                    .class("timeline-grid-line"),
                                    .style("left: \(metrics.position(for: hour) * 100)%")
                                ) {}
                            }
                            for performance in stagePerformances {
                                EventViewerTimelineCard(
                                    performance: performance,
                                    theme: theme,
                                    metrics: metrics,
                                    orientation: .horizontal
                                )
                            }
                        }
                    }
                }
        }
    }
}

struct EventViewerVerticalSchedule: HTML {
    let stages: [Performance]
    let performances: [Performance]
    let theme: EventViewerTheme

    var body: some HTML {
        let metrics = EventViewerTimelineMetrics(performances: performances)
        let columns = "4.5rem repeat(\(stages.count), minmax(15rem, 1fr))"

        div(.class("vertical-schedule")) {
                div(
                    .class("vertical-schedule-grid"),
                    .style("grid-template-columns: \(columns)")
                ) {
                    div(.class("vertical-grid-corner")) {}
                    for stage in stages {
                        div(.class("vertical-stage-header")) {
                            EventViewerStageIcon(
                                performance: stage,
                                fallbackColor: theme.accent,
                                showsStageColorBackground: true
                            )
                            h3 { stage.stage }
                        }
                    }

                    div(
                        .class("vertical-time-rail"),
                        .style("height: \(metrics.timelineHeight)px")
                    ) {
                        for hour in metrics.hours {
                            span(
                                .class("vertical-time-label"),
                                .style("top: \(metrics.position(for: hour) * 100)%")
                            ) {
                                EventViewerTimelineMetrics.hourLabel(for: hour)
                            }
                        }
                    }

                    for stage in stages {
                        let stagePerformances = performances.filter { $0.stageID == stage.stageID }
                        div(
                            .class("vertical-stage-column"),
                            .style("height: \(metrics.timelineHeight)px")
                        ) {
                            for hour in metrics.hours {
                                div(
                                    .class("timeline-grid-line"),
                                    .style("top: \(metrics.position(for: hour) * 100)%")
                                ) {}
                            }
                            for performance in stagePerformances {
                                EventViewerTimelineCard(
                                    performance: performance,
                                    theme: theme,
                                    metrics: metrics,
                                    orientation: .vertical
                                )
                            }
                        }
                    }
                }
        }
    }
}

enum EventViewerTimelineOrientation {
    case horizontal
    case vertical
}

struct EventViewerTimelineCard: HTML {
    let performance: Performance
    let theme: EventViewerTheme
    let metrics: EventViewerTimelineMetrics
    let orientation: EventViewerTimelineOrientation

    var body: some HTML {
        a(
            .href(performance.detailURL),
            .class([
                "timeline-card",
                orientation == .horizontal ? "horizontal-timeline-card" : "vertical-timeline-card"
            ]),
            .style(cardStyle)
        ) {
            h3 { performance.title }
            time { performance.timeRangeText }
        }
    }

    var cardStyle: String {
        let start = performance.startMinute ?? metrics.startMinute
        let startPosition = metrics.position(for: start)
        let duration = max(metrics.width(for: performance), 0.04)

        switch orientation {
        case .horizontal:
            return "--stage-color: \(performance.stageColor ?? theme.accent); left: \(startPosition * 100)%; width: \(duration * 100)%"
        case .vertical:
            return "--stage-color: \(performance.stageColor ?? theme.accent); top: \(startPosition * 100)%; height: \(duration * 100)%"
        }
    }
}

struct EventViewerListSchedule: HTML {
    let performances: [Performance]
    let theme: EventViewerTheme
    let isActive: Bool

    var body: some HTML {
        div(
            .class([
                "schedule-view",
                "list-view",
                isActive ? "is-active" : ""
            ]),
            .id("schedule-view-list")
        ) {
            div(.class("schedule-list")) {
                for performance in performances {
                    EventViewerScheduleRow(performance: performance, theme: theme)
                }
            }
        }
    }
}

struct EventViewerStageLane: HTML {
    let stage: Performance
    let performances: [Performance]
    let theme: EventViewerTheme

    var body: some HTML {
        section(.class("stage-lane")) {
            EventViewerStageLaneHeader(stage: stage, theme: theme)
            div(.class("stage-lane-performances")) {
                for performance in performances {
                    EventViewerScheduleCard(performance: performance, theme: theme)
                }
            }
        }
    }
}

struct EventViewerStageLaneHeader: HTML {
    let stage: Performance
    let theme: EventViewerTheme

    var body: some HTML {
        div(.class("stage-lane-header")) {
            EventViewerStageIcon(performance: stage, fallbackColor: theme.accent)
            div {
                h3 { stage.stage }
                p { "Stage" }
            }
        }
    }
}

struct EventViewerScheduleCard: HTML {
    let performance: Performance
    let theme: EventViewerTheme

    var body: some HTML {
        a(
            .href(performance.detailURL),
            .class("schedule-card"),
            .style("border-left-color: \(performance.stageColor ?? theme.accent)")
        ) {
            time { performance.time }
            h3 { performance.title }
            p { performance.stage }
        }
    }
}

struct EventViewerStageSelector: HTML {
    let performances: [Performance]
    let theme: EventViewerTheme
    let selectedStage: String?

    var stages: [Performance] {
        Self.uniqueStages(from: performances)
    }

    var resolvedSelectedStage: String? {
        let availableStages = stages.map { $0.stageID }
        if let selectedStage, availableStages.contains(selectedStage) {
            return selectedStage
        }
        return availableStages.first
    }

    static func uniqueStages(from performances: [Performance]) -> [Performance] {
        var seen = Set<String>()
        return performances.filter { seen.insert($0.stageID).inserted }
    }


    var body: some HTML {
        div(.class("stage-selector"), .id("schedule-stages")) {
            for stage in stages {
                let stageValue = stage.stageID
                a(
                    .class([
                        "stage-chip",
                        resolvedSelectedStage == stageValue ? "selected" : ""
                    ]),
                    .href(stage.scheduleURL),
                    .data("stage", value: stageValue)
                ) {
                    EventViewerStageIcon(performance: stage, fallbackColor: theme.accent)
                    span { stage.stage }
                }
            }
        }
    }
}

struct EventViewerScheduleRow: HTML {
    let performance: Performance
    let theme: EventViewerTheme

    var body: some HTML {
        a(.href(performance.detailURL), .class("schedule-row")) {
            time(.class("schedule-time")) { performance.timeRangeText }
            div(
                .class("stage-rail"),
                .style("background: \(performance.stageColor ?? theme.accent)")
            ) {}
            EventViewerStageIcon(performance: performance, fallbackColor: theme.accent)
            div(.class("schedule-copy")) {
                h3 { performance.title }
                p { "\(performance.stage) · \(performance.timeRangeText)" }
            }
        }
    }
}

struct EventViewerStageIcon: HTML {
    let performance: Performance
    let fallbackColor: String
    let showsStageColorBackground: Bool

    init(
        performance: Performance,
        fallbackColor: String,
        showsStageColorBackground: Bool = true
    ) {
        self.performance = performance
        self.fallbackColor = fallbackColor
        self.showsStageColorBackground = showsStageColorBackground
    }

    var body: some HTML {
        div(
            .class("stage-icon"),
            .style(
                showsStageColorBackground
                    ? "background: \(performance.stageColor ?? fallbackColor)"
                    : "background: transparent"
            )
        ) {
            if let stageLogoURL = performance.stageLogoURL {
                img(.src(stageLogoURL), .alt(performance.stage))
            } else {
                span(.class("stage-fallback")) { initials }
            }
        }
    }

    var initials: String {
        performance.stage
            .split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
    }
}

private extension Performance {
    var searchText: String { title + " " + stage }
    var timeRangeText: String {
        if let endTime {
            return "\(time) – \(endTime)"
        }
        return time
    }
}

private extension Contributor {
    var initials: String {
        name
            .split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
    }

    var searchText: String {
        [name, role, bio, handle ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}

private extension EventLocation {
    var mapQuery: String {
        if let latitude, let longitude {
            return "\(latitude),\(longitude)"
        }
        return address
    }

    var encodedMapQuery: String {
        mapQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mapQuery
    }

    var appleMapsURL: String {
        "https://maps.apple.com/?q=\(encodedMapQuery)"
    }

    var googleMapsURL: String {
        "https://www.google.com/maps/search/?api=1&query=\(encodedMapQuery)"
    }
}

struct EventViewerInfo: HTML {
    let model: EventModel

    var body: some HTML {
        section(.class(["section", "alt"]), .id("event-info")) {
            div(.class("section-inner")) {
                if let summary = model.summary {
                    p(.class("info-summary")) { summary }
                }
                div(.class("info-grid")) {
                    if let dateLine = model.dateLine {
                        article(.class("info-card")) {
                            h3 { "Dates" }
                            p { dateLine }
                        }
                    }
                    article(.class("info-card")) {
                        h3 { "Location" }
                        p { model.location }
                    }
                    if let timeZoneIdentifier = model.timeZoneIdentifier {
                        article(.class("info-card")) {
                            h3 { "Time zone" }
                            p { timeZoneIdentifier }
                        }
                    }
                    if let status = model.status {
                        article(.class("info-card")) {
                            h3 { "Status" }
                            p { status }
                        }
                    }
                    if let mode = model.mode {
                        article(.class("info-card")) {
                            h3 { "Mode" }
                            p { mode }
                        }
                    }
                    if let organizer = model.organizer {
                        article(.class("info-card")) {
                            h3 { "Organizer" }
                            p { organizer }
                        }
                    }
                }
            }
        }
    }
}

struct EventViewerChoices: HTML {
    let title: String
    let choices: [ViewerChoice]
    var body: some HTML {
        if !choices.isEmpty {
            nav(.class("viewer-choices"), .custom(name: "aria-label", value: title)) {
                for choice in choices {
                    a(.href(choice.url), .class(choice.selected ? "selected" : "")) { choice.title }
                }
            }
        }
    }
}

struct EventViewerPerformanceDetail: HTML {
    let performance: Performance
    let timeZone: String?

    var body: some HTML {
        section(.class("feature-section")) {
            div(.class("feature-section-inner")) {
                a(.href(performance.scheduleURL)) { "Back to schedule" }
                h2 { performance.title }
                if let date = performance.dateLine { p { date } }
                p { performance.timeRangeText + (timeZone.map { " · " + $0 } ?? "") }
                p { a(.href(performance.scheduleURL)) { performance.stage } }
                if let description = performance.description {
                    p(.style("white-space: pre-wrap")) { description }
                }
                if !performance.credits.isEmpty {
                    h3 { "Contributors" }
                    ul {
                        for credit in performance.credits {
                            li {
                                if let url = credit.url { a(.href(url)) { credit.text } }
                                else { span { credit.text } }
                            }
                        }
                    }
                }
                for image in performance.images {
                    if let url = image.imageURL {
                        img(.src(url), .alt(image.title), .style("max-width: 100%; height: auto"))
                    }
                }
                for media in performance.mediaLinks {
                    if let url = media.url { p { a(.href(url)) { media.text } } }
                }
            }
        }
    }
}
