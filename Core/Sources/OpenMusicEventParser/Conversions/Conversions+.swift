//
//  FatalError.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/29/25.
//

import FileTree

extension Conversions {
    struct FatalError<Input, Output>: Conversion {
        func apply(_ input: Input) throws -> Output {
            fatalError()
        }

        func unapply(_ output: Output) throws -> Input {
            fatalError()
        }
    }
}

extension Conversion {
    func mapValues<OutputElement: Sendable, NewOutput: Sendable>(
        apply: @Sendable @escaping (OutputElement) throws -> NewOutput,
        unapply: @Sendable @escaping (NewOutput) throws -> OutputElement
    ) -> some Conversion<Input, [NewOutput]> where Output == [OutputElement] {
        self.map(Conversions.MapValues(AnyConversion(apply: apply, unapply: unapply)))
    }

    func mapValues<OutputElement: Sendable, NewOutput: Sendable, C>(
        _ conversion: some Conversion<OutputElement, NewOutput>
    ) -> some Conversion<Input, [NewOutput]>
    where Output == [OutputElement] {
        self.map(Conversions.MapValues(conversion))
    }

    func mapValues<OutputElement: Sendable, NewOutput: Sendable, C>(
        @ConversionBuilder _ conversion: () -> some Conversion<OutputElement, NewOutput>
    ) -> some Conversion<Input, [NewOutput]>
    where Output == [OutputElement] {
        self.map(Conversions.MapValues(conversion))
    }
}



struct MarkdownWithFrontMatterConversion<T: Codable & Sendable>: Conversion {
    typealias Input = String
    typealias Output = MarkdownWithFrontMatter<T>

    func apply(_ input: String) throws -> MarkdownWithFrontMatter<T> {
        return try MarkdownWithFrontMatter.Parser().parse(input)
    }

    func unapply(_ output: MarkdownWithFrontMatter<T>) throws -> String {
        var outputString: Substring = ""

        try MarkdownWithFrontMatter.Parser().print(output, into: &outputString)

        return String(outputString)
    }
}


extension Conversions {
    struct SubstringToYaml<T: Codable>: Conversion {
        var body: some Conversion<Substring, T> {
            Conversions.SubstringToString()
            Conversions.DataToString().inverted()
            YamlConversion<T>()
        }
    }
}

typealias SubstringToYaml = Conversions.SubstringToYaml
