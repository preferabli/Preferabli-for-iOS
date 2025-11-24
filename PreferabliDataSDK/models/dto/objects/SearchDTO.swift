//
//  SearchDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

/// `Search` has no `id` in your SwiftData model; upsert will key on `text`.
public struct SearchDTO: Decodable, Sendable {
    public let count: Int?
    public let last_searched: Date?
    public let text: String
}
