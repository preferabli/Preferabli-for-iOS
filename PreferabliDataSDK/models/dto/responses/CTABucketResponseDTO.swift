//
//  CTABucketResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/23/26.
//

import Foundation

struct CTABucketResponseDTO: Decodable {
    let section: String?
    let market_id: Int?
    let items: [CTABucketDTO]
}
