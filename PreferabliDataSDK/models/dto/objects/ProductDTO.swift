//
//  ProductDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct VariantDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let num_dollar_signs: Int?
    public let price: Decimal?
    public let recommendable: Bool?
    public let year: Int
    public let primary_image: MediaDTO?
    public let product_id: Int?
}

public struct ProductDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let brand: String?
    public let decant: Bool?
    public let grape: String?
    public let brand_lat: Double?
    public let brand_lon: Double?
    public let show_year_dropdown: Bool?
    public let recommendable: Bool?
    public let name: String?
    public let region: String?
    public let category: String?
    public let subcategory: String?
    public let type: String?
    public let brand_id: Int?
    public let hash: String?
    public let country_code: String?
    public let primary_image: MediaDTO?
    public let variants: [VariantDTO]?
    public let latest_variant_num_dollar_signs: Int?
    
    init(
        id: Int,
        name: String?,
        category: String?,
        subcategory: String?,
        type: String?
    ) {
        self.id = id
        self.created_at = nil
        self.updated_at = nil
        self.brand = nil
        self.decant = nil
        self.grape = nil
        self.brand_lat = nil
        self.brand_lon = nil
        self.show_year_dropdown = nil
        self.recommendable = nil
        self.name = name
        self.region = nil
        self.category = category
        self.subcategory = subcategory
        self.type = type
        self.brand_id = nil
        self.hash = nil
        self.country_code = nil
        self.primary_image = nil
        self.variants = nil
        self.latest_variant_num_dollar_signs = nil
    }
}
