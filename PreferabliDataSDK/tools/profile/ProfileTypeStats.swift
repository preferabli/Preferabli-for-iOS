//
//  ProfileTypeStats.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/2/25.
//

import Foundation
import CoreGraphics

/// Per-kind statistics (appealing/unappealing counts, scores, etc).
public struct ProfileTypeStats: Codable, Hashable {
    public var appealingCount: Int
    public var unappealingCount: Int
    public var myScore: Int          // e.g. score_red, score_whiskey, etc.
    public var topScore: CGFloat     // Andrew’s “top score” sum

    public var myStyleCount: Int { appealingCount + unappealingCount }

    public init(
        appealingCount: Int = 0,
        unappealingCount: Int = 0,
        myScore: Int = 0,
        topScore: CGFloat = 0
    ) {
        self.appealingCount = appealingCount
        self.unappealingCount = unappealingCount
        self.myScore = myScore
        self.topScore = topScore
    }
}

/// All statistics for a profile.
public struct ProfileStatistics: Codable, Hashable {
    public struct TopStyleSummary: Codable, Hashable {
        public var styleId: Int
        public var name: String
        public var imageURL: URL?
    }

    /// Per-kind stats; there should be entries for all 14 kinds,
    /// but the dictionary is kept flexible for forwards compatibility.
    public var perType: [ProfileProductKind: ProfileTypeStats]

    /// Total count of preference styles considered (appealing + unappealing).
    public var preferenceCount: Int

    /// Optional details about the single top style (for UI).
    public var topStyle: TopStyleSummary?

    public init(
        perType: [ProfileProductKind: ProfileTypeStats] = [:],
        preferenceCount: Int = 0,
        topStyle: TopStyleSummary? = nil
    ) {
        self.perType = perType
        self.preferenceCount = preferenceCount
        self.topStyle = topStyle
    }
}

// MARK: - Level

public enum Level: Int, Codable {
    case one  = 1
    case two  = 2
    case three = 3
    case four = 4
    case five = 5
    case none = 0

    public var levelLimit: Int {
        switch self {
        case .one:   return 10
        case .two:   return 22
        case .three: return 40
        case .four:  return 80
        case .five:  return 100
        case .none:  return 1
        }
    }

    public var levelLowerLimit: Int {
        switch self {
        case .one:   return 0
        case .two:   return 10
        case .three: return 22
        case .four:  return 40
        case .five:  return 80
        case .none:  return -1
        }
    }
}
