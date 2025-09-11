//
//  SortType.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/21/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import UIKit
import CoreData

/// Used for sorting everything from products to collections.
public class Sort {
    
    public var type : SortType
    public var ascending : Bool
    
    public init(type : SortType, ascending : Bool) {
        self.type = type
        self.ascending = ascending
    }
}

/// The type of sort to be applied.
public enum SortType {
    case PRICE
    case DATE
    case ALPHABETICAL
    case REGION
    case GRAPE
    case RATING
    case TYPE
    case LAST_UPDATED
    case DISTANCE
    case DEFAULT

    internal func getType() -> String {
        switch self {
        case .PRICE:
            return "price"
        case .DATE:
            return "date"
        case .ALPHABETICAL:
            return "alphabetical"
        case .REGION:
            return "region"
        case .GRAPE:
            return "grape"
        case .RATING:
            return "rating"
        case .TYPE:
            return "type"
        case .LAST_UPDATED:
            return "last_updated"
        case .DISTANCE:
            return "distance"
        case .DEFAULT:
            return "default"
        }
    }
    
    static internal func getSortTypeFromString(value : String) -> SortType {
            switch value.lowercased() {
            case "price":
                return .PRICE
            case "date":
                return .DATE
            case "alphabetical":
                return .ALPHABETICAL
            case "region":
                return .REGION
            case "grape":
                return .GRAPE
            case "rating":
                return .RATING
            case "type":
                return .TYPE
            case "last_updated":
                return .LAST_UPDATED
            case "distance":
                return .DISTANCE
            case "default":
                return .DEFAULT
            default:
                return .DEFAULT
            }
    }
}
