//
//  Analytics.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 9/2/25.
//

import Foundation
import Mixpanel

enum Analytics {
    static func track(_ payload: [String: Any]) {
        var dict = payload
        guard let event = dict.removeValue(forKey: "event") as? String else { return }
        track(event, dict)
    }

    static func track(_ event: String, _ properties: [String: Any] = [:]) {
        let props = convertDictionaryToMixpanelProperties(dictionary: properties)
        Mixpanel.mainInstance().track(event: event, properties: props)
    }
    
    static func convertDictionaryToMixpanelProperties(dictionary : [String : Any]) -> [String : MixpanelType] {
        var properties = [String : MixpanelType]()
        for (key, value) in dictionary {
            if let val = value as? String {
                properties[key] = val
            } else if let val = value as? Int {
                properties[key] = val
            } else if let val = value as? Bool {
                properties[key] = val
            } else if let val = value as? Double {
                properties[key] = val
            } else if let val = value as? Float {
                properties[key] = val
            } else if let val = value as? Date {
                properties[key] = val
            } else if let val = value as? URL {
                properties[key] = val
            } else if let val = value as? NSNull {
                properties[key] = val
            } else if let val = value as? [MixpanelType] {
                properties[key] = val
            }
        }
        return properties
    }
}
