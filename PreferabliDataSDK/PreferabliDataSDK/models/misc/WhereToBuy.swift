//
//  WhereToBuy.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/14/23.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation

/// Container object returned by ``Preferabli/whereToBuy(product_id:fulfill_sort:append_nonconforming_results:lock_to_integration:onCompletion:onFailure:)``. This object will include an array of either ``MerchantProductLink``s (if sorted by price) or ``Venue``s (if sorted by distance).
public class WhereToBuy {
    
    public var links = Array<MerchantProductLink>()
    public var venues = Array<Venue>()
    
    internal init(links : [MerchantProductLink], venues : [Venue]) {
        self.links = links
        self.venues = venues
    }
}
