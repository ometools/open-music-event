//
//  YamlConversion.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 10/22/24.
//


import FileTree
import Foundation
import Yams

extension Conversions {

    struct YamlConversion<T: Codable>: Conversion {
        typealias Input = Data
        typealias Output = T
        
        init(_ type: T.Type = T.self) { }
        
        func apply(_ input: Data) throws -> T {
            try YAMLDecoder().decode(T.self, from: input)
        }
        
        func unapply(_ output: T) throws -> Data {
            try Data(YAMLEncoder().encode(output).utf8)
        }
    }
}
typealias YMLConversion = Conversions.YamlConversion
