//
//  UserCollectionDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct UserCollectionDTO: Decodable, Sendable {
    public let id: Int
    public let relationship_type: String?
    public let collection_id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let collection: CollectionDTO
}
