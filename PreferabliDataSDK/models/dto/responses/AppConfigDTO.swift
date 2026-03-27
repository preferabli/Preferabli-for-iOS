//
//  AppConfigDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/23/26.
//


struct AppConfigDTO: Decodable {
    let should_update: ShouldUpdateDTO?

    struct ShouldUpdateDTO: Decodable {
        let display: Bool?
        let message: String?
        let version: Int?
        let url: String?
    }
}
