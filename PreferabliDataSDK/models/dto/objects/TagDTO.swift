//
//  TagDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct TagDTO: Decodable, Sendable {
    public let id: Int
    public let collection_id: Int
    public let comment: String?
    public let created_at: Date?
    public let location: String?
    public let badge: String?
    public let tagged_in_collection_id: Int?
    public let tagged_in_channel_id: Int?
    public let tagged_in_channel_name: String?
    public let type: String?
    public let updated_at: Date?
    public let user_id: Int?
    public let value: String?
    public let bin: String?
    public let variant_id: Int
    public let quantity: Int?
    public let format_ml: Int?
    public let price: Decimal?
    public let customer_id: Int?
}
