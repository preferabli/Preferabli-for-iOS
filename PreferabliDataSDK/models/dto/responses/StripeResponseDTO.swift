//
//  StripeResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/15/26.
//

import Foundation

public struct StripeResponseDTO: Decodable {
    public let customer_id: String
    public let ephemeral_key: String
    public let client_secret: String
    public let intent_id: String
}
