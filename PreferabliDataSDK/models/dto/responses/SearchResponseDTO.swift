//
//  SearchResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/17/25.
//

import Foundation

struct SearchResponseDTO: Decodable {
    let products: [ProductDTO]
}
