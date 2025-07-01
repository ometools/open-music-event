//
//  AsyncMap.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 11/1/24.
//

import Testing


struct AsyncSequenceTests {
    @Test()
    func concurrentMap() async throws {
        let result = try await [1,2,3,4,5].concurrentMap {
            try await Task.sleep(for: .seconds(Double.random(in: 0...1)))
            return $0 + 1
        }

        #expect(result == [2,3,4,5,6])
    }
}
