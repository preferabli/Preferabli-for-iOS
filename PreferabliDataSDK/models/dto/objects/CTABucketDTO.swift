//
//  CTABucketDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/23/26.
//

import Foundation

public struct CTABucketDTO: Decodable, Sendable {
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
}
