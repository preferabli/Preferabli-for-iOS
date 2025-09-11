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
public class MerchantProductLink : BaseObject {
    
    public var variant_id: Int?
    public var product_id: Int?
    public var merchant_variant_id: String?
    public var merchant_product_id: String?
    public var price_currency: String?
    public var year: Int?
    public var format_ml: Int?
    public var landing_url: String?
    public var image_url: String?
    public var product_name: String?
    public var price: String?
    
    /// All of the venues that include the specific item in the inventory collection. Call Where to Buy to populate.
    public var venues: [Venue]?
    /// True if this item does not conform to all Where to Buy query parameters.
    public var nonconforming_result: Bool
    
    internal init(map : [String : Any]) {
        variant_id = map["variant_id"] as? Int
        product_id = map["product_id"] as? Int
        merchant_variant_id = map["merchant_variant_id"] as? String
        merchant_product_id = map["merchant_product_id"] as? String
        price_currency = map["price_currency"] as? String
        nonconforming_result = map["nonconforming_result"] as? Bool ?? false
        year = map["year"] as? Int
        format_ml = map["format_ml"] as? Int
        landing_url = map["landing_url"] as? String
        product_name = map["product_name"] as? String
        price = map["price"] as? String
        image_url = map["image_url"] as? String

        super.init(id: map["id"] as? Int ?? 0)
    }
    
    /// Filter links by submitted search terms.
    /// - Parameters:
    ///   - lookups: an array of links to be filtered.
    ///   - search_text: search terms as a string.
    /// - Returns: a filtered array of links.
    static public func filterLinks(lookups : Array<MerchantProductLink>, search_text : String) -> Array<MerchantProductLink> {
        var filteredLookups = Array<MerchantProductLink>()
        if (search_text.isEmptyOrWhitespace()) {
            filteredLookups = lookups
        } else {
            let searchTerms = search_text.components(separatedBy: " ")
            filteredLookups = lookups.filter() {
                for searchTerm in searchTerms {
                    if ($0.filterLink(search_term: searchTerm)) {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
        }
        
        filteredLookups = filteredLookups.filter() { $0.getVenues().count > 0 }
        
        return filteredLookups
    }
    
    internal func filterLink(search_term : String) -> Bool {
        if (search_term.isEmptyOrWhitespace()) {
            return true
        } else if (product_name?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else {
            for venue in getVenues() {
                if (venue.filterVenue(search_term: search_term)) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Gets an array of Where to Buy venues.
    /// - Returns: an array of ``Venue``. Returns an empty array if not populated.
    public func getVenues() -> Array<Venue> {
        if (venues == nil) {
            venues = Array<Venue>()
        }
        return venues!
    }
    
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
    public func getImage(width : Float, height : Float, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: image_url, width: width, height: height, quality: quality)
    }
    
    /// Gets price formatted with the currency.
    /// - Returns: a string representing the localized price.
    public func getFormattedPrice() -> String {
        if (price == nil) {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.locale = PreferabliTools.getLocaleForCurrencyCode(currencyCode: price_currency)
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber.init(value: Double(price!)!))!
    }
}

// All of our Preferabli API actions go here.
extension MerchantProductLink {
//    /// See ``Preferabli/whereToBuy(product_id:fulfill_sort:append_nonconforming_results:lock_to_integration:onCompletion:onFailure:)``.
//    public func whereToBuy(fulfill_sort : FulfillSort = FulfillSort.init(), append_nonconforming_results : Bool = true, lock_to_integration : Bool = true,  onCompletion: @escaping (WhereToBuy) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
//        if (product_id != nil) {
//            Preferabli.main.whereToBuy(product_id: product_id!, fulfill_sort: fulfill_sort, append_nonconforming_results: append_nonconforming_results, lock_to_integration: lock_to_integration, onCompletion: onCompletion, onFailure: onFailure)
//        }
//    }
//
//    /// See ``Preferabli/rateProduct(product_id:year:rating:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func rate(rating : RatingLevel, location : String? = nil, notes : String? = nil, price : Decimal? = nil, quantity : Int? = nil, format_ml : Int? = nil, onCompletion : @escaping (Product) -> () = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        if (product_id != nil) {
//            Preferabli.main.rateProduct(product_id: product_id!, year: year ?? Variant.CURRENT_VARIANT_YEAR, rating: rating, location: location, notes: notes, price: price, quantity: quantity, format_ml: format_ml, onCompletion: onCompletion, onFailure: onFailure)
//        }
//    }
//    
//    /// See ``Preferabli/lttt(product_id:year:collection_id:include_merchant_links:onCompletion:onFailure:)``.
//    public func lttt(collection_id : Int = Preferabli.PRIMARY_INVENTORY_ID, onCompletion: @escaping ([Int]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
//        if (product_id != nil) {
//            Preferabli.main.lttt(product_id: product_id!, collection_id: collection_id, onCompletion: onCompletion, onFailure: onFailure)
//        }
//    }
//    
//    /// See ``Preferabli/getPreferabliScore(product_id:year:onCompletion:onFailure:)``.
//    public func getPreferabliScore(onCompletion : @escaping (PreferenceData) -> ()  = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        if (product_id != nil) {
//            Preferabli.main.getPreferabliScore(product_id: product_id!, year: year ?? Variant.CURRENT_VARIANT_YEAR, onCompletion: onCompletion, onFailure: onFailure)
//        }
//    }
}
