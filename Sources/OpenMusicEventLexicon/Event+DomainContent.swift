import ATProto
import Foundation

extension Event {
    /// Constructs domain content, not a publishable OME record. Native record
    /// construction, decoding, encoding, and reference validation stay strict.
    public init(
        projecting sourceURI: ATProto.URI,
        cid: ATProto.CID,
        projectionVersion: Int,
        name: String,
        createdAt: ATProto.DateTime
    ) throws {
        try StringFormat.validate(sourceURI.description, format: "at-uri")
        guard case .did = sourceURI.authority,
              let collection = sourceURI.collection, sourceURI.rkey != nil,
              collection.rawValue != Self.lexiconID.rawValue,
              projectionVersion > 0 else {
            throw ValidationError("External domain projection requires a source record identity and positive adapter version")
        }
        self.id = sourceURI
        self.cid = cid
        self.projectionVersion = projectionVersion
        self.name = name
        self.createdAt = createdAt
        _ = try domainContent()
    }

    /// OME-shaped content for AppView domain reads and adapter validation. This
    /// deliberately does not encode a publication envelope or validate ownership.
    /// Publication must use RecordCodable and validateReferences instead.
    public func domainContent() throws -> Lexicon.JSONValue {
        let values: [String: Lexicon.JSONValue] = try [
            "name": name.encodeLexicon(), "createdAt": createdAt.encodeLexicon(),
            "timeZone": timeZone?.identifier.encodeLexicon() ?? .null,
            "description": description.encodeLexicon(), "start": start.encodeLexicon(),
            "end": end.encodeLexicon(), "status": status.encodeLexicon(),
            "mode": mode.encodeLexicon(), "locations": locations.encodeLexicon(),
            "links": links.encodeLexicon(), "media": media.encodeLexicon(),
            "programs": programs.encodeLexicon(), "schedules": schedules.encodeLexicon(),
            "rsvpExpected": rsvpExpected.encodeLexicon(), "categories": categories.encodeLexicon(),
            "siteMap": siteMap?.encodeLexicon() ?? .null,
        ]
        let schema = try Self.domainSchema.get()
        guard Set(values.keys) == Set(schema.fields.map(\.name)) else {
            throw ValidationError("Event domain content must cover every lexicon field")
        }
        var object: [String: Lexicon.JSONValue] = ["$type": .string(Self.lexiconID.rawValue)]
        for field in schema.fields {
            let value = values[field.name]!
            if field.omitIfNil && value == .null { continue }
            object[field.name] = value
        }
        let content = Lexicon.JSONValue.object(object)
        try schema.validator.validate(content, against: schema.definition, id: Self.lexiconID)
        return content
    }

    public static func validateDomainField(_ value: Lexicon.JSONValue, named name: String) throws {
        let schema = try domainSchema.get()
        guard let field = schema.fields.first(where: { $0.name == name }) else {
            throw ValidationError("Unknown Event field", path: [name])
        }
        try schema.validator.validate(value, against: field.schema, id: lexiconID, path: [name])
    }

    private struct DomainSchema: Sendable {
        let fields: [LexiconFieldDescription]
        let definition: Definition
        let validator: SchemaValidator
    }

    private static let domainSchema: Result<DomainSchema, any Error> = Result {
        try DomainSchema(fields: lexiconFields, definition: lexiconDefinition,
            validator: SchemaValidator(definitions: LexiconExporter.validationDefinitions(for: [Self.self])))
    }
}
