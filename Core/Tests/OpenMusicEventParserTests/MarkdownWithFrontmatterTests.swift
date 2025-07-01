//
//  File.swift
//  
//
//  Created by Woodrow Melling on 8/18/24.
//

import Foundation
import XCTest
@testable import OpenMusicEventParser
import Testing
import CustomDump
import Parsing

struct MarkdownWithFrontmatterTests {

    @Test(.tags(.frontmatter))
    func simpleFrontmatterRoundtripping() throws {
        struct Person: Codable, Equatable {
            var name: String
            var age: Int
        }

        let originalText = """
        ---
        name: blob
        age: 29
        ---
        """

        var text = Substring(originalText)
        let result = try Parsers.FrontMatter<Person>().parse(&text)
        #expect(result == Person(name: "blob", age: 29))
        try Parsers.FrontMatter<Person>().print(result, into: &text)
        #expect(originalText == text)
    }

    @Test(.tags(.frontmatter))
    func markdownWithFrontMatterRoundtripping() throws {
        struct PersonFrontMatter: Codable, Equatable {
            var name: String
            var age: Int
        }

        let originalText = """
        ---
        name: Blob
        age: 29
        ---
        Blob once went through parthenogenesis and created Blob Jr.
        """

        var text = Substring(originalText)
        let parserPrinter = MarkdownWithFrontMatter<PersonFrontMatter>.Parser()
        let result = try parserPrinter.parse(&text)
        #expect(
            result == MarkdownWithFrontMatter(
                frontMatter: PersonFrontMatter(name: "Blob", age: 29),
                body: "Blob once went through parthenogenesis and created Blob Jr."
            )
        )
        try parserPrinter.print(result, into: &text)
        #expect(originalText == text)
    }

    @Test(.tags(.frontmatter))
    func nilFrontMatter() throws {
        struct PersonFrontMatter: Codable, Equatable {
            var name: String
            var age: Int
        }

        let originalText = """
        Blob once went through parthenogenesis and created Blob Jr.
        """

        var text = Substring(originalText)
        let parserPrinter = MarkdownWithFrontMatter<PersonFrontMatter>.Parser()
        let result = try parserPrinter.parse(&text)
        #expect(
            result == MarkdownWithFrontMatter(
                frontMatter: nil,
                body: "Blob once went through parthenogenesis and created Blob Jr."
            )
        )
        try parserPrinter.print(result, into: &text)
        #expect(originalText == text)
    }

    @Test(.tags(.frontmatter))
    func optionalButHonestFrontMatter() throws {
        struct PersonFrontMatter: Codable, Equatable {
            var name: String
            var age: Int
        }

        let originalText = """
        ---
        name: Blob
        age: 29
        ---
        Blob once went through parthenogenesis and created Blob Jr.
        """

        var text = Substring(originalText)
        let parserPrinter = MarkdownWithFrontMatter<PersonFrontMatter>.Parser()
        let result = try parserPrinter.parse(&text)
        #expect(
            result == MarkdownWithFrontMatter(
                frontMatter: PersonFrontMatter(name: "Blob", age: 29),
                body: "Blob once went through parthenogenesis and created Blob Jr."
            )
        )
        try parserPrinter.print(result, into: &text)
        #expect(originalText == text)
    }
}
