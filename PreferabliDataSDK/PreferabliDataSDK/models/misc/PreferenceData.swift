//
//  PreferenceData.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation

/// Indicates a user's level of preference for a specific ``Product``.
public class PreferenceData {
    
    public var title : String?
    public var details : String?
    
    /// How confident we are in our rating.
    internal var confidence_code : Int?
    
    /// A score from 85 - 100 which informs us how likely a user is to enjoy a product. *Nil if the user will not like the product.*
    public var formatted_predict_rating : Int?
    
    internal init(title : String? = nil, details : String? = nil, confidence_code : Int?, formatted_predict_rating : Int?) {
        self.title = title
        self.details = details
        self.confidence_code = confidence_code
        self.formatted_predict_rating = formatted_predict_rating
    }
    
    internal init(map: [String : Any]) {
        self.title = map["title"] as? String
        self.details = map["details"] as? String
        self.confidence_code = map["confidence_code"] as? Int
        self.formatted_predict_rating = map["formatted_predict_rating"] as? Int
    }
    
    /// Get a fully written out response to whether or not a user like's a product.
    /// - Returns: a formatted response as a string.
    public func getMessage() -> String {
        var first = ""
        if (formatted_predict_rating != nil) {
            first = NSNumber.init(value: formatted_predict_rating!).stringValue + " - "
        }
        return first + title! + " - " + details!
    }
}
