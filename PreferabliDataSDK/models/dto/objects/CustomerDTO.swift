//
//  CustomerDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct CustomerDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let avatar_url: String?
    public let merchant_user_email_address: String?
    public let merchant_user_id: String?
    public let merchant_user_name: String?
    public let merchant_user_display_name: String?
    public let role: String?
}
