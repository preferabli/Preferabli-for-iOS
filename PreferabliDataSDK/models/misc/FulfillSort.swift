//
//  FulfillSortType.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/14/21.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// Used to sort within ``Preferabli/whereToBuy(product_id:fulfill_sort:append_nonconforming_results:lock_to_integration:onCompletion:onFailure:)``.
public class FulfillSort : Sort {
    
    public var include_shipping : Bool
    public var include_delivery : Bool
    public var include_pickup : Bool
    public var include_in_person : Bool

    public var variant_year : Int
    public var distance_miles : Int
    /// *If sorting by distance, location MUST be present!*
    public var location : LocationDTO?

    public init(type : SortType = SortType.PRICE, ascending : Bool = true, include_shipping : Bool = true, include_delivery : Bool = true, include_pickup : Bool = true, include_in_person : Bool = true, variant_year : Int = Variant.NON_VARIANT, distance_miles : Int = 75, location : LocationDTO? = nil) {
        self.include_shipping = include_shipping
        self.include_delivery = include_delivery
        self.include_pickup = include_pickup
        self.include_in_person = include_in_person
        self.variant_year = variant_year
        self.distance_miles = distance_miles
        self.location = location
        super.init(type: type, ascending: ascending)
    }
}
