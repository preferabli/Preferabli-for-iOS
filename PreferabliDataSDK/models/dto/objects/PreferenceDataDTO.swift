//
//  PreferenceDataDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// Indicates a user's level of preference for a specific ``Product``.
public struct PreferenceDataDTO: Decodable, Sendable {
    
    public let title : String?
    public let details : String?
    
    /// How confident we are in our rating.
    internal let confidence_code : Int?
    
    /// A score from 85 - 100 which informs us how likely a user is to enjoy a product. *Nil if the user will not like the product.*
    public let formatted_predict_rating : Int?
    
    /// Get a fully written out response to whether or not a user like's a product.
    /// - Returns: a formatted response as a string.
    public func getMessage() -> String {
        var first = ""
        if (formatted_predict_rating != nil) {
            first = NSNumber.init(value: formatted_predict_rating!).stringValue + " - "
        }
        return first + title! + " - " + details!
    }
    
    init(title: String? = nil, details: String? = nil, confidence_code: Int? = nil, formatted_predict_rating: Int? = nil) {
        self.title = title
        self.details = details
        self.confidence_code = confidence_code
        self.formatted_predict_rating = formatted_predict_rating
    }
}
