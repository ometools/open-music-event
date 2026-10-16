import Elementary

public struct EventBrowseRow: Equatable, Sendable {
    public var title: String
    public var date: String?
    public var imageURL: String?
    public var url: String
    public init(title: String, date: String?, imageURL: String?, url: String) {
        self.title = title; self.date = date; self.imageURL = imageURL; self.url = url
    }
}

public struct EventBrowseSection: Equatable, Sendable {
    public var title: String
    public var events: [EventBrowseRow]
    public init(title: String, events: [EventBrowseRow]) { self.title = title; self.events = events }
}

public struct EventBrowseHTML: HTMLDocument {
    public var sections: [EventBrowseSection]
    public var query: String
    public var day: String
    public var mode: String
    public var sort: String
    public init(sections: [EventBrowseSection], query: String, day: String, mode: String, sort: String) {
        self.sections = sections; self.query = query; self.day = day; self.mode = mode; self.sort = sort
    }
    public var title: String { "Browse · Open Music Event" }
    public var lang: String { "en" }
    public var head: some HTML {
        meta(.name(.viewport), .content("width=device-width, initial-scale=1"))
        style { HTMLRaw("""
        :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, -apple-system, sans-serif; background: #060708; color: #f5f7f7; }
        * { box-sizing: border-box; } body { margin: 0; } a { color: inherit; } input, select, button { font: inherit; }
        header { border-bottom: 1px solid #30363a; padding: 1rem 1.25rem; }
        .brand { display: inline-flex; align-items: center; gap: .6rem; text-decoration: none; }
        .brand img { width: 44px; height: 44px; object-fit: contain; }
        .brand span { font-size: .85rem; font-weight: 700; letter-spacing: .2em; text-transform: uppercase; background: linear-gradient(90deg,#47a9a8,#6650d3 34%,#d34f7a 68%,#d8823d); background-clip: text; color: transparent; }
        main { max-width: 54rem; margin: auto; padding: 1.5rem 1.25rem 4rem; }
        h1 { margin: 0 0 1.25rem; font-size: 2rem; } h2 { font-size: .9rem; color: #a8b0b3; margin: 2rem 0 .65rem; }
        form { display: flex; flex-wrap: wrap; gap: .8rem; padding-bottom: 1rem; border-bottom: 1px solid #30363a; }
        label { display: grid; gap: .35rem; font-size: .8rem; color: #a8b0b3; } .search { flex: 1 1 100%; }
        input, select, button { min-height: 44px; padding: .65rem; border: 1px solid #30363a; border-radius: .5rem; background: #121517; color: #f5f7f7; max-width: 100%; }
        button, .clear { align-self: end; } button { cursor: pointer; } .clear { padding: .75rem .25rem; }
        .event { display: flex; align-items: flex-start; gap: 12px; padding: 1rem 0; border-bottom: 1px solid #30363a; text-decoration: none; }
        .event:hover, .event:focus-visible { background: #121517; } .art { flex: 0 0 60px; width: 60px; height: 60px; border-radius: 8px; background: #1c2023; display: grid; place-items: center; overflow: hidden; }
        .art img { width: 100%; height: 100%; object-fit: cover; } .event-copy { min-width: 0; display: grid; gap: 4px; } .event strong { font-size: 1rem; overflow-wrap: anywhere; } .date, .organizer, .empty { color: #a8b0b3; font-size: .9rem; } .date { font-size: .8rem; }
        @media(max-width: 36rem) { main { padding: 1.25rem 1rem 3rem; } label:not(.search) { flex: 1 1 40%; } .brand span { font-size: .7rem; } }
        """) }
    }
    public var body: some HTML {
        header {
            a(.class("brand"), .href("/")) {
                img(.src(EventViewerTheme.ome.brandMarkURL), .alt(""))
                span { "Open Music Event" }
            }
        }
        main {
            h1 { "Browse" }
            form(.method(.get), .action("/")) {
                label(.class("search")) { "Search events"; input(.type(.search), .name("q"), .value(query), .placeholder("Search events")) }
                label { "Date"; input(.type(.date), .name("day"), .value(day)) }
                label {
                    "Format"
                    select(.name("mode")) {
                        for choice in [("", "All formats"), ("inperson", "In person"), ("virtual", "Virtual"), ("hybrid", "Hybrid")] {
                            option(.value(choice.0)) { choice.1 }.attributes(.selected, when: mode == choice.0)
                        }
                    }
                }
                label {
                    "Sort"
                    select(.name("sort")) {
                        option(.value("soonest")) { "Soonest first" }.attributes(.selected, when: sort == "soonest")
                        option(.value("name")) { "Name" }.attributes(.selected, when: sort == "name")
                    }
                }
                button(.type(.submit)) { "Apply" }
                a(.class("clear"), .href("/")) { "Clear filters" }
            }
            if sections.isEmpty {
                h2 { "No Events" }
                p(.class("empty")) { "No events match the current browse selection." }
            }
            for group in sections {
                section {
                    h2 { group.title }
                    if group.events.isEmpty { p(.class("empty")) { "Nothing is happening right now." } }
                    for event in group.events {
                        a(.class("event"), .href(event.url)) {
                            span(.class("art")) {
                                if let image = event.imageURL { img(.src(image), .alt(""), .custom(name: "loading", value: "lazy")) }
                                else { span(.custom(name: "aria-hidden", value: "true")) { "♫" } }
                            }
                            span(.class("event-copy")) {
                                if let date = event.date { span(.class("date")) { date } }
                                strong { event.title }
                                span(.class("organizer")) { "Organizer" }
                            }
                        }
                    }
                }
            }
        }
    }
}
