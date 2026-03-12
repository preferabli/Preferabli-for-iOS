//
//  FLTTTResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/12/26.
//

import Foundation

struct FLTTTResponseDTO: Decodable {
    let title: String?
    let details: String?
    let products: [ProductDTO]
}
