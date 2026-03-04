//
//  BucketsLoader.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/23/26.
//


import Foundation

actor BucketsLoader {
    static let shared = BucketsLoader()
    private var inflight: Task<[Int], Error>?

    func run(_ makeRequest: @escaping @Sendable () async throws -> [Int]) async throws -> [Int] {
        if let t = inflight {
            return try await t.value
        }
        let t = Task<[Int], Error> {
            try await makeRequest()
        }
        inflight = t
        defer { inflight = nil }
        return try await t.value
    }
}
