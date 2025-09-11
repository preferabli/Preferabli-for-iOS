//
//  URLExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/19/17.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

extension URL {
    public var queryItems: [String: String]? {
        if let urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: true) {
            if let queryItems = urlComponents.queryItems {
                var params = [String: String]()
                queryItems.forEach{
                    params[$0.name] = $0.value
                }
                return params
            }
        }
        return nil
    }
}
