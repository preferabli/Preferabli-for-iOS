//
//  APIError.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/11/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// Represents an error returned from our API.
internal class APIError {
    
    internal var code : Int?
    internal var message : String?
    
    internal init(code : Int, message: String) {
        self.code = code
        self.message = message
    }
    
    internal init(map: [String : Any]) {
        self.code = map["code"] as? Int
        self.message = map["message"] as? String
    }
}
