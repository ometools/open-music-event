public struct EventViewerTheme: Equatable, Sendable {
    public var productName: String
    public var brandMarkURL: String
    public var canvas: String
    public var surface: String
    public var raisedSurface: String
    public var ink: String
    public var mutedInk: String
    public var softInk: String
    public var line: String
    public var lineSoft: String
    public var accent: String
    public var accentSoft: String
    public var secondaryAccent: String
    public var tertiaryAccent: String
    public var warmAccent: String

    public init(
        productName: String,
        brandMarkURL: String,
        canvas: String,
        surface: String,
        raisedSurface: String,
        ink: String,
        mutedInk: String,
        softInk: String,
        line: String,
        lineSoft: String,
        accent: String,
        accentSoft: String,
        secondaryAccent: String,
        tertiaryAccent: String,
        warmAccent: String
    ) {
        self.productName = productName
        self.brandMarkURL = brandMarkURL
        self.canvas = canvas
        self.surface = surface
        self.raisedSurface = raisedSurface
        self.ink = ink
        self.mutedInk = mutedInk
        self.softInk = softInk
        self.line = line
        self.lineSoft = lineSoft
        self.accent = accent
        self.accentSoft = accentSoft
        self.secondaryAccent = secondaryAccent
        self.tertiaryAccent = tertiaryAccent
        self.warmAccent = warmAccent
    }
}

public extension EventViewerTheme {
    static let ome = EventViewerTheme(
        productName: "Open Music Event",
        brandMarkURL: "/assets/ome-mark.jpg",
        canvas: "#060708",
        surface: "#0d0f10",
        raisedSurface: "#121517",
        ink: "#f5f7f7",
        mutedInk: "#a8b0b3",
        softInk: "#d9e0e2",
        line: "#30363a",
        lineSoft: "rgba(255, 255, 255, 0.1)",
        accent: "#78e0d6",
        accentSoft: "rgba(120, 224, 214, 0.08)",
        secondaryAccent: "#a8d98e",
        tertiaryAccent: "#f18aa8",
        warmAccent: "#ffc473"
    )

    /// Event identity comes from the event record; the web shell stays OME.
    static let wickedWoods = ome
}
