//
//  SDKConfig.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/14/25.
//

import Foundation


internal enum SDKConfig {
    static var mixpanelKey: String {
        // Fail fast in debug if config is missing
        guard
            let url = Bundle.module.url(forResource: "PreferabliConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let key = plist["mixpanelKey"] as? String,
            !key.isEmpty
        else {
            assertionFailure("PreferabliDataSDK: mixpanelKey missing in PreferabliConfig.plist")
            return ""
        }

        return key
    }
    
    static var qrKey: String {
        // Fail fast in debug if config is missing
        guard
            let url = Bundle.module.url(forResource: "PreferabliConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let key = plist["qrKey"] as? String,
            !key.isEmpty
        else {
            assertionFailure("PreferabliDataSDK: mixpanelKey missing in PreferabliConfig.plist")
            return ""
        }

        return key
    }
}
