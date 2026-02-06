//
//  MerchantProductLink.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/28/20.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//
//

import Foundation
import CoreData


/// This is the link between a Preferabli ``Product`` and a merchant product.  If returned as part of ``WhereToBuy``, will contain an array of ``Venue`` as ``venues``.
public struct MerchantProductLink :  Decodable, Sendable {
    
    public let id: Int
    public let variant_id: Int
    public let merchant_variant_id: String?
    public let merchant_product_id: String?
    public let price_currency: String?
    public let variant_year: Int?
    public let format_ml: Int?
    public let landing_url: String?
    public let image_url: String?
    public let product_name: String?
    public let price: String?
    public let channel_name: String?
    public let venues: [VenueDTO]?
    
    /// True if this item does not conform to all Where to Buy query parameters.
    public let nonconforming_result: Bool
    

    /// Sorts links by price.
    /// - Parameters:
    ///   - links: an array of links to be sorted.
    ///   - ascending: true if you want results returned in ascending order. Defaults to *true*.
    /// - Returns: a sorted array of links.
    static public func sortLinksByPrice(links : Array<MerchantProductLink>, ascending : Bool = true) -> [MerchantProductLink] {
        return links.sorted {
            let integer1 = Float($0.price ?? "") ?? -1
            let price1 = NSNumber(value: integer1)
            
            let integer2 = Float($1.price ?? "") ?? -1
            let price2 = NSNumber(value: integer2)
            
            if (price1 == price2) {
                return String.alphaSortIgnoreThe(x: $0.product_name ?? "", y: $1.product_name ?? "")
            }
            
            if (ascending) {
                return price1.floatValue < price2.floatValue
            } else {
                return price1.floatValue > price2.floatValue
            }
        }
    }
    
    /// Get the link's image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: image_url, width: width, height: height, quality: quality)
    }
    
    /// Gets price formatted with the currency.
    /// - Returns: a string representing the localized price.
    public func getFormattedPrice() -> String {
        guard let price, !price.isEmpty else { return "" }

        // Parse defensively (handles "12.50" or "12,50")
        let normalized = price.replacingOccurrences(of: ",", with: ".")
        let value = Double(normalized) ?? 0

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency

        // Use the user's locale for separators (., vs ,)
        formatter.locale = Locale.current

        // But force the currency that the API told us
        if let code = price_currency, !code.isEmpty {
            formatter.currencyCode = code
        }

        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}
