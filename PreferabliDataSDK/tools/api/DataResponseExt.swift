//
//  DataResponseExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/23/18.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import Alamofire

extension DataResponse {
    internal func isNotCached() -> Bool {
        var eTag = response!.allHeaderFields["ETag"] as? String
        if (eTag.isEmptyOrWhitespace) {
            eTag = response!.allHeaderFields["Etag"] as? String
        }
        let isEtagged = eTag.isEmptyOrWhitespace || Storage.getKeyStore().string(forKey: "etag " + request!.url!.absoluteString) != eTag
        Storage.getKeyStore().set(eTag, forKey: "etag " + request!.url!.absoluteString)
        return isEtagged
    }
}
