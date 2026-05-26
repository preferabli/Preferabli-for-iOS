//
//  CTABucketDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/23/26.
//

import Foundation

public struct CTABucketDTO: Decodable, Sendable {
    let id: Int
    let section: String?
    let name: String?
    let order: Int?
    let item_width: Int?
    let item_height: Int?
    let item_corner_radius: Int?
    let type: String?
    let market_id: Int?
    let affiliate_id: Int?
    let items: [CTABucketItemDTO]?
    let created_at: Date?
    let updated_at: Date?
}

public struct CTABucketItemDTO: Decodable, Sendable {
    public let id: Int
    public let badge_icon: String?
    public let badge_color_primary: String?
    public let badge_color_secondary: String?
    public let order: Int?
    public let color_secondary: String?
    public let color_primary: String?
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
