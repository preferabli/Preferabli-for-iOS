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

    /// Total number of styles per type (from legacy `getTotalStyleCount`).
    ///
    /// NOTE: Beer includes legacy RTD total here (111 + 103 = 214).
    var totalStyleCount: Int {
        switch self {
        case .red:        return 209
        case .white:      return 139
        case .rose:       return 14
        case .sparkling:  return 33
        case .fortified:  return 24
        case .whiskey:    return 72
        case .mezcal:     return 45
        case .beer:       return 111
        case .cheese:     return 132
        case .vodka:      return 10
        case .gin:        return 10
        case .rum:        return 10
        case .sake:       return 10
        case .cocktail:   return 10
        }
    }

    /// Highest score per type (from legacy `getHighestScore`).
    ///
    /// NOTE: Beer includes legacy RTD highest score here (152 + 10 = 162).
    var highestScore: Int {
        switch self {
        case .red:        return 626
        case .white:      return 456
        case .rose:       return 48
        case .sparkling:  return 96
        case .fortified:  return 88
        case .whiskey:    return 164
        case .mezcal:     return 66
        case .beer:       return 152
        case .cheese:     return 82
        case .vodka:      return 10
        case .gin:        return 10
        case .rum:        return 10
        case .sake:       return 10
        case .cocktail:   return 10
        }
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
