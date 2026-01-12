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
    public var myScore: Int
    public var topScore: CGFloat

    public var ratingCount: Int        // ✅ NEW

    public var myStyleCount: Int { appealingCount + unappealingCount }

    public init(
        appealingCount: Int = 0,
        unappealingCount: Int = 0,
        myScore: Int = 0,
        topScore: CGFloat = 0,
        ratingCount: Int = 0          // ✅ NEW
    ) {
        self.appealingCount = appealingCount
        self.unappealingCount = unappealingCount
        self.myScore = myScore
        self.topScore = topScore
        self.ratingCount = ratingCount
    }
}


/// All statistics for a profile.
public struct ProfileStatistics: Codable, Hashable {

    // ✅ NEW: sanity / ownership header
    public var ownerKey: Int
    public var generatedAt: Date

    public struct TopStyleSummary: Codable, Hashable {
        public var styleId: Int
        public var name: String
        public var imageURL: URL?

        public var productCategory: String?
        public var productSubcategory: String?
        public var productType: String?

        public init(
            styleId: Int,
            name: String,
            imageURL: URL? = nil,
            productCategory: String? = nil,
            productSubcategory: String? = nil,
            productType: String? = nil
        ) {
            self.styleId = styleId
            self.name = name
            self.imageURL = imageURL
            self.productCategory = productCategory
            self.productSubcategory = productSubcategory
            self.productType = productType
        }
    }

    public struct TopRegionSummary: Codable, Hashable {
        public var region: String
        public var count: Int
        public var countryCode: String?
        public var lat: Double?
        public var lon: Double?

        public init(
            region: String,
            count: Int,
            countryCode: String? = nil,
            lat: Double? = nil,
            lon: Double? = nil
        ) {
            self.region = region
            self.count = count
            self.countryCode = countryCode
            self.lat = lat
            self.lon = lon
        }
    }

    public var perType: [ProfileProductKind: ProfileTypeStats]
    public var preferenceCount: Int
    public var topStyle: TopStyleSummary?
    public var topStylePerType: [ProfileProductKind: TopStyleSummary]

    public var topRegionPerType: [ProfileProductKind: TopRegionSummary]
    public var topRegionOverall: TopRegionSummary?

    public init(
        ownerKey: Int = 0,
        generatedAt: Date = Date(),
        perType: [ProfileProductKind: ProfileTypeStats] = [:],
        preferenceCount: Int = 0,
        topStyle: TopStyleSummary? = nil,
        topStylePerType: [ProfileProductKind: TopStyleSummary] = [:],   // ✅ NEW
        topRegionPerType: [ProfileProductKind: TopRegionSummary] = [:],
        topRegionOverall: TopRegionSummary? = nil
    ) {
        self.ownerKey = ownerKey
        self.generatedAt = generatedAt
        self.perType = perType
        self.preferenceCount = preferenceCount
        self.topStyle = topStyle
        self.topStylePerType = topStylePerType                            // ✅ NEW
        self.topRegionPerType = topRegionPerType
        self.topRegionOverall = topRegionOverall
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
