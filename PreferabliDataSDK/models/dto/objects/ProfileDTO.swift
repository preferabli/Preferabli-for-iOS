//
//  ProfileDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct ProfileDTO: Decodable, Sendable {
    public let id: Int
    // Add fields when you decide to persist them.
}

public struct StyleDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let desc: String?
    public let name: String?
    public let type: String?
    public let primary_image_url: String?
    public let product_category: String?
}


public struct ProfileStyleDTO: Decodable, Sendable {
    public let id: Int
    public let conflict: Bool?
    public let order_profile: Int?
    public let order_recommend: Int?
    public let rating: Int?
    public let strength: Int?
    public let style_id: Int?
    public let recommend: Bool?
    public let refine: Bool?
    public let keywords: String?
    public let created_at: Date?
    public let updated_at: Date?
    public let style: StyleDTO?
    public let profile: ProfileDTO?
}
