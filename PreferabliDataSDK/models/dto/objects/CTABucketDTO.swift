//
//  CTABucketDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/23/26.
//

import Foundation

public struct CTAPageDTO: Decodable, Sendable {
    let id: Int
    let slug: String?
    let name: String?
    let market_id: Int?
    let affiliate_id: Int?
    let page_bucket_associations: [CTABucketAssociationDTO]?
    let created_at: Date?
    let updated_at: Date?
}

public struct CTABucketAssociationDTO: Decodable, Sendable {
    let id: Int
    let order: Int?
    let bucket: CTABucketDTO
    let created_at: Date?
    let updated_at: Date?
}

public struct CTABucketDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let item_width: Int?
    let item_height: Int?
    let item_corner_radius: Int?
    let type: String?
    let deeplink_url: String?
    let bucket_item_associations: [CTABucketItemAssociationDTO]?
    let created_at: Date?
    let updated_at: Date?
}

public struct CTABucketItemAssociationDTO: Decodable, Sendable {
    let id: Int
    let order: Int?
    let item: CTABucketItemDTO
    let created_at: Date?
    let updated_at: Date?
}

public struct CTABucketItemDTO: Decodable, Sendable {
    public let id: Int
    public let is_centered: Bool?
    public let half_gradient: Bool?
    public let badge_placement: String?
    public let badge_icon: String?
    public let badge_color_hex_primary: String?
    public let badge_color_hex_secondary: String?
    public let badge_text_color_hex: String?
    public let text_color_hex: String?
    public let color_hex_secondary: String?
    public let color_hex_primary: String?
    public let badge_gradient_css: String?
    public let gradient_css: String?
    public let deeplink_url: String?
    public let badge_title: String?
    public let title: String?
    public let description: String?
    public let created_at: Date?
    public let updated_at: Date?
    public let primary_image: MediaDTO?
    public let sub_image_1: MediaDTO?
    public let sub_image_2: MediaDTO?
}
