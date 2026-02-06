//
//  PreferabliUserDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct PreferabliUserDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?

    public let country: String?
    public let display_name: String?
    public let email: String?
    public let is_team_preferabli: Bool?
    public let fname: String?
    public let lname: String?
    public let claim_code: String?
    public let has_merchant_access: Bool?
    public let has_kiosks: Bool?
    public let zip_code: String?
    public let intercom_hmac: String?
    public let rating_collection_id: Int?
    public let provided_feedback_at: Date?
    public let wishlist_collection_id: Int?
    public let avatar_background_color_hex: String?
    public let avatar_text_color_hex: String?

    public let avatar: MediaDTO?
}
