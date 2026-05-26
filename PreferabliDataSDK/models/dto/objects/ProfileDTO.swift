//
//  ProfileDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct ProfileDTO: Decodable, Sendable {
    public let id: Int
    public let preference_styles : [ProfileStyleDTO]
    public let user_id: Int?
    public let customer_id: Int?
    public let score: Int?
    public let score_red: Int?
    public let score_white: Int?
    public let score_rose: Int?
    public let score_sparkling: Int?
    public let score_fortified: Int?
    public let score_whiskey: Int?
    public let score_tequila: Int?
    public let score_vodka: Int?
    public let score_gin: Int?
    public let score_rum: Int?
    public let score_sake: Int?
    public let score_cocktail: Int?
    public let score_beer: Int?
    public let score_cheese: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct StyleDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let description: String?
    public let name: String?
    public let type: String
    public let primary_image_url: String?
    public let product_category: String?
    public let is_global: Bool?
    public let show_map: Bool?
    public let locations : [LocationDTO]
}


public struct ProfileStyleDTO: Decodable, Sendable {
    public let id: Int
    public let conflict: Bool?
    public let order_profile: Int?
    public let order_recommend: Int?
    public let rating: Int?
    public let strength: Int?
    public let style_id: Int
    public let recommend: Bool?
    public let refine: Bool?
    public let keywords: String?
    public let created_at: Date?
    public let updated_at: Date?
    public let style: StyleDTO?
    public let profile: ProfileDTO?
}
