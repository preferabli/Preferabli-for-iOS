//
//  StripeMethodResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/20/26.
//

import Foundation

public struct StripeMethodResponseDTO: Decodable {
    public let customer_id: String
    public let payment_method_id: String
    public let intent_id: String
}
