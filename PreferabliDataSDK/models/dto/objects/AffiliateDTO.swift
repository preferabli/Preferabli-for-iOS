//
//  AffiliateDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/30/26.
//

struct AffiliateDTO: Decodable {
    let id: Int
    let affiliate_code: String?
    let affiliate_param: String?
    let description: String?
    let filter_visible: Bool?
    let header_image_url: String?
    let logo_image_url: String?
    let market_id: Int?
    let name: String?
    let order: Int?
    let slug: String?
    let title: String?
    let visible: Bool?

    // Present on top-level affiliate response
    let experiences: [ExperienceDTO]?
}
