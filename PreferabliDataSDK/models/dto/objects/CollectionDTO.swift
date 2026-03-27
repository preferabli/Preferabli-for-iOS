//
//  CollectionDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct CollectionOrderDTO: Decodable, Sendable {
    public let id: Int
    public let tag_id: Int
    public let order: Int
    public let updated_at: Date?
    public let created_at: Date?
}

public struct CollectionGroupDTO: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let order: Int?
    public let orderings_count: Int?
    public let orderings: [CollectionOrderDTO]?
    public let updated_at: Date?
    public let created_at: Date?
}

public struct CollectionTraitDTO: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let order: Int?
    public let restrict_to_ring_it: Bool?
    public let updated_at: Date?
    public let created_at: Date?
}

public struct CollectionVersionDTO: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let order: Int?
    public let groups: [CollectionGroupDTO]?
    public let updated_at: Date?
    public let created_at: Date?
}

public struct CollectionDTO: Decodable, Sendable {
    public let id: Int
    public let channel_id: Int?
    public let sort_channel_id: Int?
    public let code: String?
    public let description: String?
    public let end_date: Date?
    public let updated_at: Date?
    public let auto_wili: Bool?
    public let has_image: Bool?
    public let is_pinned: Bool?
    public let display_time: Bool?
    public let is_browsable: Bool?
    public let is_my_cellar: Bool?
    public let lbs_order: Int?
    public let product_count: Int?
    public let name: String?
    public let badge_method: String?
    public let currency: String?
    public let timezone: String?
    public let published: Bool?
    public let archived: Bool?
    public let display_price: Bool?
    public let display_quantity: Bool?
    public let display_bin: Bool?
    public let has_predict_order: Bool?
    public let is_randomized: Bool?
    public let display_group_headings: Bool?
    public let is_blind: Bool?
    public let start_date: Date?
    public let created_at: Date?
    public let venue_id: Int?
    public let sort_channel_name: String?
    public let location_based_recs: Bool?
    public let primary_image: MediaDTO?
    public let versions: [CollectionVersionDTO]?
    public let traits: [CollectionTraitDTO]?
}
