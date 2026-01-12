//
//  ProfileProductKind.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/2/25.
//

import Foundation
import CoreGraphics

/// Analytics product kinds (used for stats / levels, not necessarily 1:1 with API models).
public enum ProfileProductKind: String, CaseIterable, Codable, Hashable, Sendable {
    case red
    case white
    case rose
    case sparkling
    case fortified
    case whiskey
    case mezcal
    case beer          // Beer + RTD combined
    case cheese
    case vodka
    case gin
    case rum
    case sake
    case cocktail
}

public extension ProfileProductKind {

    /// Whether this kind is a wine (used for combined wine stats).
    var isWine: Bool {
        switch self {
        case .red, .white, .rose, .sparkling, .fortified:
            return true
        default:
            return false
        }
    }
    
    var asProductType: ProductType? {
        switch self {
        case .red:       return .RED
        case .white:     return .WHITE
        case .rose:      return .ROSE
        case .sparkling: return .SPARKLING
        case .fortified: return .FORTIFIED
        default:         return nil
        }
    }

    var asProductCategory: ProductCategory {
        switch self {
        case .whiskey:  return .WHISKEY
        case .mezcal:   return .MEZCAL
        case .beer:     return .BEER
        case .cheese:   return .CHEESE
        case .vodka:    return .VODKA
        case .gin:      return .GIN
        case .rum:      return .RUM
        case .sake:     return .SAKE
        case .cocktail: return .COCKTAIL
        default:        return .WINE
        }
    }

    /// Total number of styles per type (from legacy `getTotalStyleCount`).
    ///
    /// NOTE: Beer includes legacy RTD total here (111 + 103 = 214).
    var totalStyleCount: Int {
        switch self {
        case .red:        return 213
        case .white:      return 143
        case .rose:       return 16
        case .sparkling:  return 37
        case .fortified:  return 24
        case .whiskey:    return 72
        case .mezcal:     return 45
        case .beer:       return 214
        case .cheese:     return 132
        case .vodka:      return 37
        case .gin:        return 40
        case .rum:        return 50
        case .sake:       return 93
        case .cocktail:   return 218
        }
    }

    /// Highest score per type (from legacy `getHighestScore`).
    ///
    /// NOTE: Beer includes legacy RTD highest score here (152 + 10 = 162).
    var highestScore: Int {
        return totalStyleCount * 4
    }

    /// Multipliers used in Andrew's "top score" formula.
    /// (Same as legacy, with RTD folded into Beer.)
    var topScoreMultiplier: CGFloat {
        switch self {
        case .red:        return 0.1249125
        case .white:      return 0.1163348
        case .rose:       return 0.0685858
        case .sparkling:  return 0.0862457
        case .fortified:  return 0.0796469
        case .whiskey:    return 0.1025299
        case .mezcal:     return 0.0897207
        case .beer:       return 0.1067362
        case .cheese:     return 0.1152489
        case .vodka:      return 0
        case .gin:        return 0
        case .rum:        return 0
        case .sake:       return 0
        case .cocktail:   return 0
        }
    }

    /// All wine kinds as a convenience.
    static var wineKinds: [ProfileProductKind] {
        return [.red, .white, .rose, .sparkling, .fortified]
    }
}
