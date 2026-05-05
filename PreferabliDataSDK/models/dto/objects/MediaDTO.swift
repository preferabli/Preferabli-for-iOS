//
//  MediaDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct MediaDTO: Decodable, Sendable {
    public let id: Int
    public let path: String?
    public let type: String?
}
