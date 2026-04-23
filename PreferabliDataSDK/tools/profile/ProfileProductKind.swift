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
    var totalStyleCount: Int {
        switch self {
        case .red:        return 213
        case .white:      return 143
        case .rose:       return 16
        case .sparkling:  return 37
        case .fortified:  return 24
        case .whiskey:    return 72
        case .mezcal:     return 45
        case .beer:       return 197
        case .cheese:     return 132
        case .vodka:      return 37
        case .gin:        return 40
        case .rum:        return 50
        case .sake:       return 93
        case .cocktail:   return 219
        }
    }

    /// Total styles across all kinds.
    static var totalStyleCountAcrossAllKinds: Int {
        allCases.reduce(0) { $0 + $1.totalStyleCount }
    }

    /// Highest score per type (from legacy `getHighestScore`).
    var highestScore: Int {
        return totalStyleCount * 4
    }

    /// Multiplier based on this kind's share of total styles across all kinds.
    var topScoreMultiplier: CGFloat {
        let total = Self.totalStyleCountAcrossAllKinds
        guard total > 0 else { return 0 }
        return CGFloat(totalStyleCount) / CGFloat(total)
    }

    /// All wine kinds as a convenience.
    static var wineKinds: [ProfileProductKind] {
        return [.red, .white, .rose, .sparkling, .fortified]
    }
}
