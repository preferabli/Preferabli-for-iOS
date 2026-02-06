//
//  WhereToBuyDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/3/26.
//

import Foundation

public struct WhereToBuyDTO: Decodable {
    public let venue_results: [VenueDTO]?
    public let lookup_results: [MerchantProductLink]?
}
