
//
//  RepresentationCodable.swift
//  event-viewer
//
//  Created by Woodrow Melling on 3/16/25.
//

import Foundation

typealias RepresentationCodable = RepresentationDecodable & RepresentationEncodable
protocol RepresentationDecodable: Decodable {
    associatedtype Representation: Decodable
    init(from representation: Representation) throws
}
extension RepresentationDecodable {
    public init(from decoder: any Decoder) throws {
        let representation = try Representation(from: decoder)
        try self.init(from: representation)
    }
}

protocol RepresentationEncodable: Encodable {
    associatedtype Representation: Encodable
    func toRepresentation() throws -> Representation
}

extension RepresentationEncodable {
    public func encode(to encoder: any Encoder) throws {
        let representation = try toRepresentation()
        try representation.encode(to: encoder)
    }
}

