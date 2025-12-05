//
//  ProfileAnalytics.swift
//  Preferabli
//
//  Modern analytics helper for profile statistics & levels.
//  - RTD combined with Beer (14 base kinds).
//  - Supports combined wine stats (all wine kinds together).
//

import Foundation
import CoreGraphics

/// How to rank "top" product kinds.
public enum TopProductMetric {
    case breadth        // % of styles explored (breadth)
    case depth          // % of score vs highest (depth)
    case appealingRatio // appealing / (appealing + unappealing)
    case topScore       // Andrew’s topScore metric
}

public enum ProfileAnalytics {

    // MARK: - Storage

    /// Key for storing stats blob in your existing key store.
    /// Feel free to version this if you change structure later.
    private static let statsKey = "profile_statistics_v2"

    // MARK: - Decoupled inputs

    /// Lightweight profile scores input (map from your Profile model).
    public struct ProfileInput {
        public var score_red: Int
        public var score_white: Int
        public var score_rose: Int
        public var score_sparkling: Int
        public var score_fortified: Int
        public var score_whiskey: Int
        public var score_mezcal: Int
        public var score_beer: Int
        public var score_cheese: Int
        public var score_vodka: Int
        public var score_gin: Int
        public var score_rum: Int
        public var score_sake: Int
        public var score_cocktail: Int

        public init(
            score_red: Int = 0,
            score_white: Int = 0,
            score_rose: Int = 0,
            score_sparkling: Int = 0,
            score_fortified: Int = 0,
            score_whiskey: Int = 0,
            score_mezcal: Int = 0,
            score_beer: Int = 0,
            score_cheese: Int = 0,
            score_vodka: Int = 0,
            score_gin: Int = 0,
            score_rum: Int = 0,
            score_sake: Int = 0,
            score_cocktail: Int = 0
        ) {
            self.score_red = score_red
            self.score_white = score_white
            self.score_rose = score_rose
            self.score_sparkling = score_sparkling
            self.score_fortified = score_fortified
            self.score_whiskey = score_whiskey
            self.score_mezcal = score_mezcal
            self.score_beer = score_beer
            self.score_cheese = score_cheese
            self.score_vodka = score_vodka
            self.score_gin = score_gin
            self.score_rum = score_rum
            self.score_sake = score_sake
            self.score_cocktail = score_cocktail
        }
    }

    /// Minimal input needed per preference style.
    public struct PreferenceStyleInput {
        public var kind: ProfileProductKind
        public var rating: Int?          // was Double
        public var orderRecommend: Int?  // was Double
        public var isAppealing: Bool
        public var isUnappealing: Bool
        public var styleId: Int
        public var styleName: String?
        public var styleImageURL: URL?

        public init(
            kind: ProfileProductKind,
            rating: Int?,
            orderRecommend: Int?,
            isAppealing: Bool,
            isUnappealing: Bool,
            styleId: Int,
            styleName: String?,
            styleImageURL: URL?
        ) {
            self.kind = kind
            self.rating = rating
            self.orderRecommend = orderRecommend
            self.isAppealing = isAppealing
            self.isUnappealing = isUnappealing
            self.styleId = styleId
            self.styleName = styleName
            self.styleImageURL = styleImageURL
        }
    }


    // MARK: - Public API

    /// Recompute stats for the given profile and preference styles and save them.
    ///
    /// You call this **after** you upsert the profile + styles into your persistence layer.
    public static func recomputeAndStoreStats(
        profile: ProfileInput,
        preferenceStyles: [PreferenceStyleInput]
    ) {
        let stats = computeStats(profile: profile, preferenceStyles: preferenceStyles)
        save(stats: stats)
    }

    /// Load stats from storage (if previously computed).
    public static func loadStats() -> ProfileStatistics? {
        guard let data = Storage.getKeyStore().data(forKey: statsKey) else { return nil }
        return try? JSONDecoder().decode(ProfileStatistics.self, from: data)
    }

    /// Top product kinds according to a metric (default: Andrew’s top score).
    public static func topProductKinds(
        metric: TopProductMetric = .topScore
    ) -> [ProfileProductKind] {
        guard let stats = loadStats() else { return [] }
        return topProductKinds(in: stats, metric: metric)
    }

    /// Level for a specific kind (e.g. `.red`, `.whiskey`).
    public static func level(for kind: ProfileProductKind) -> Level {
        guard let stats = loadStats(),
              let typeStats = stats.perType[kind],
              typeStats.myStyleCount > 0 else {
            return .none
        }

        let avg = averagePercent(for: kind, stats: stats)
        if avg < Double(Level.one.levelLimit)   { return .one }
        if avg < Double(Level.two.levelLimit)   { return .two }
        if avg < Double(Level.three.levelLimit) { return .three }
        if avg < Double(Level.four.levelLimit)  { return .four }
        return .five
    }

    /// Progress within the current level (0–100).
    public static func levelProgress(for kind: ProfileProductKind) -> Int {
        guard let stats = loadStats(),
              let typeStats = stats.perType[kind],
              typeStats.myStyleCount > 0 else {
            return 0
        }

        let lvl = level(for: kind)
        if lvl == .none { return 0 }
        if lvl == .five { return 100 }

        let avg = averagePercent(for: kind, stats: stats)

        let range     = Double(lvl.levelLimit - lvl.levelLowerLimit)
        let intoLevel = Double(avg - Double(lvl.levelLowerLimit))
        if range <= 0 { return 0 }

        let pct = Int((intoLevel / range) * 100)
        return max(0, min(100, pct))
    }

    // MARK: - Combined Wine Stats (all wine kinds together)

    /// Combined statistics across all wine kinds (.red, .white, .rose, .sparkling, .fortified).
    public static func combinedWineStats() -> ProfileTypeStats? {
        guard let stats = loadStats() else { return nil }

        var combined = ProfileTypeStats()

        for kind in ProfileProductKind.wineKinds {
            guard let typeStats = stats.perType[kind] else { continue }
            combined.appealingCount    += typeStats.appealingCount
            combined.unappealingCount  += typeStats.unappealingCount
            combined.myScore           += typeStats.myScore
            combined.topScore          += typeStats.topScore
        }

        // If we never added anything, there are no wine stats.
        if combined.myStyleCount == 0 && combined.myScore == 0 {
            return nil
        }

        return combined
    }

    /// Combined wine level (using total styles + total highest scores for all wine kinds).
    public static func combinedWineLevel() -> Level {
        guard let combined = combinedWineStats() else { return .none }

        let totalStyles = ProfileProductKind.wineKinds
            .map(\.totalStyleCount)
            .reduce(0, +)

        let totalHighest = ProfileProductKind.wineKinds
            .map(\.highestScore)
            .reduce(0, +)

        if combined.myStyleCount == 0 || totalStyles == 0 || totalHighest == 0 {
            return .none
        }

        let breadth = (Double(combined.myStyleCount) / Double(totalStyles)) * 100
        let depth   = (Double(combined.myScore)      / Double(totalHighest)) * 100
        let average = (breadth + depth) / 2

        if average < Double(Level.one.levelLimit)   { return .one }
        if average < Double(Level.two.levelLimit)   { return .two }
        if average < Double(Level.three.levelLimit) { return .three }
        if average < Double(Level.four.levelLimit)  { return .four }
        return .five
    }

    /// Combined wine level progress within current level (0–100).
    public static func combinedWineLevelProgress() -> Int {
        guard let combined = combinedWineStats() else { return 0 }

        let totalStyles = ProfileProductKind.wineKinds
            .map(\.totalStyleCount)
            .reduce(0, +)

        let totalHighest = ProfileProductKind.wineKinds
            .map(\.highestScore)
            .reduce(0, +)

        if combined.myStyleCount == 0 || totalStyles == 0 || totalHighest == 0 {
            return 0
        }

        let breadth = (Double(combined.myStyleCount) / Double(totalStyles)) * 100
        let depth   = (Double(combined.myScore)      / Double(totalHighest)) * 100
        let average = (breadth + depth) / 2

        let lvl = combinedWineLevel()
        if lvl == .none { return 0 }
        if lvl == .five { return 100 }

        let range     = Double(lvl.levelLimit - lvl.levelLowerLimit)
        let intoLevel = Double(average - Double(lvl.levelLowerLimit))
        if range <= 0 { return 0 }

        let pct = Int((intoLevel / range) * 100)
        return max(0, min(100, pct))
    }

    // MARK: - Core computation

    private static func computeStats(
        profile: ProfileInput,
        preferenceStyles: [PreferenceStyleInput]
    ) -> ProfileStatistics {
        var perType: [ProfileProductKind: ProfileTypeStats] = [:]
        var preferenceCount = 0

        // 1. Seed perType with scores from profile.
        func score(for kind: ProfileProductKind) -> Int {
            switch kind {
            case .red:       return profile.score_red
            case .white:     return profile.score_white
            case .rose:      return profile.score_rose
            case .sparkling: return profile.score_sparkling
            case .fortified: return profile.score_fortified
            case .whiskey:   return profile.score_whiskey
            case .mezcal:    return profile.score_mezcal
            case .beer:      return profile.score_beer       // Beer + RTD
            case .cheese:    return profile.score_cheese
            case .vodka:     return profile.score_vodka
            case .gin:       return profile.score_gin
            case .rum:       return profile.score_rum
            case .sake:      return profile.score_sake
            case .cocktail:  return profile.score_cocktail
            }
        }

        for kind in ProfileProductKind.allCases {
            perType[kind] = ProfileTypeStats(
                appealingCount: 0,
                unappealingCount: 0,
                myScore: score(for: kind),
                topScore: 0
            )
        }

        // 2. Walk through preference styles: counts + topScore components.
        var appealingStylesForTop: [PreferenceStyleInput] = []

        for ps in preferenceStyles {
            // Andrew’s topScore formula using Int → Double only for math.
            if let orderInt = ps.orderRecommend,
               orderInt != 0,
               let ratingInt = ps.rating {
                let rating   = Double(ratingInt)
                let orderRec = Double(orderInt)
                let multiplier = ps.kind.topScoreMultiplier
                let delta = CGFloat(rating / orderRec) * multiplier
                perType[ps.kind]?.topScore += delta
            }

            if ps.isAppealing {
                preferenceCount += 1
                perType[ps.kind]?.appealingCount += 1

                if let orderInt = ps.orderRecommend, orderInt != 0 {
                    appealingStylesForTop.append(ps)
                }
            } else if ps.isUnappealing {
                preferenceCount += 1
                perType[ps.kind]?.unappealingCount += 1
            }
        }

        // 3. Find "top style" similar to legacy approach.
        let topStyleSummary = computeTopStyle(from: appealingStylesForTop)

        return ProfileStatistics(
            perType: perType,
            preferenceCount: preferenceCount,
            topStyle: topStyleSummary
        )
    }

    /// Legacy-like top style selection.
    private static func computeTopStyle(
        from styles: [PreferenceStyleInput]
    ) -> ProfileStatistics.TopStyleSummary? {
        guard !styles.isEmpty else { return nil }

        // Max by rating, then by orderRecommend, treating nil as 0.
        guard let best = styles.max(by: { lhs, rhs in
            let lr = lhs.rating ?? 0
            let rr = rhs.rating ?? 0
            if lr == rr {
                let lo = lhs.orderRecommend ?? 0
                let ro = rhs.orderRecommend ?? 0
                return lo < ro
            } else {
                return lr < rr
            }
        }) else {
            return nil
        }

        return .init(
            styleId: best.styleId,
            name: best.styleName ?? "Unknown",
            imageURL: best.styleImageURL
        )
    }


    private static func save(stats: ProfileStatistics) {
        if let data = try? JSONEncoder().encode(stats) {
            Storage.getKeyStore().set(data, forKey: statsKey)
        }
    }

    // MARK: - Metric helpers

    private static func topProductKinds(
        in stats: ProfileStatistics,
        metric: TopProductMetric
    ) -> [ProfileProductKind] {

        let pairs: [(ProfileProductKind, Double)] = ProfileProductKind.allCases.compactMap { kind in
            guard let typeStats = stats.perType[kind] else { return nil }

            let value: Double
            switch metric {
            case .breadth:
                let total = Double(kind.totalStyleCount)
                value = total > 0
                    ? Double(typeStats.myStyleCount) / total * 100
                    : 0

            case .depth:
                let maxScore = Double(kind.highestScore)
                value = maxScore > 0
                    ? Double(typeStats.myScore) / maxScore * 100
                    : 0

            case .appealingRatio:
                let denom = Double(typeStats.myStyleCount)
                value = denom > 0
                    ? Double(typeStats.appealingCount) / denom * 100
                    : 0

            case .topScore:
                value = Double(typeStats.topScore * 1000) // scale for int-like behavior
            }

            return (kind, value)
        }

        return pairs
            .sorted { $0.1 > $1.1 } // descending
            .map { $0.0 }
    }

    /// Average percent across breadth (styles) and depth (score).
    private static func averagePercent(
        for kind: ProfileProductKind,
        stats: ProfileStatistics
    ) -> Double {
        guard let typeStats = stats.perType[kind] else { return 0 }

        let breadth: Double = {
            let myCount = Double(typeStats.myStyleCount)
            let total   = Double(kind.totalStyleCount)
            return total > 0 ? (myCount / total) * 100 : 0
        }()

        let depth: Double = {
            let myScore  = Double(typeStats.myScore)
            let maxScore = Double(kind.highestScore)
            return maxScore > 0 ? (myScore / maxScore) * 100 : 0
        }()

        return (breadth + depth) / 2
    }
}

// MARK: - SwiftData Profile helper

extension ProfileAnalytics.ProfileInput {

    /// Convenience initializer to build analytics input from your SwiftData Profile.
    ///
    /// - All optional scores are coalesced to 0.
    /// - `score_tequila` on Profile is used for `.mezcal` analytics.
    init(from profile: Profile) {
        self.init(
            score_red:       profile.score_red       ?? 0,
            score_white:     profile.score_white     ?? 0,
            score_rose:      profile.score_rose      ?? 0,
            score_sparkling: profile.score_sparkling ?? 0,
            score_fortified: profile.score_fortified ?? 0,
            score_whiskey:   profile.score_whiskey   ?? 0,

            // Mezcal in analytics is backed by `score_tequila` from Profile
            score_mezcal:    profile.score_tequila   ?? 0,

            // Beer in analytics already includes “RTD-like” categories.
            score_beer:      profile.score_beer      ?? 0,

            score_cheese:    profile.score_cheese    ?? 0,
            score_vodka:     profile.score_vodka     ?? 0,
            score_gin:       profile.score_gin       ?? 0,

            score_rum:       profile.score_rum       ?? 0,
            score_sake:      profile.score_sake      ?? 0,
            score_cocktail:  profile.score_cocktail  ?? 0
        )
    }
}

/// Optional convenience so you can call this right after you upsert a Profile.
extension ProfileAnalytics {
    public static func recomputeAndStoreStats(for profile: Profile) {
        let profileInput = ProfileInput(from: profile)

        let prefInputs: [PreferenceStyleInput] = profile.profile_styles.compactMap { ps in
            guard let kind = ps.analyticsKind(),
                  let style = ps.style else {
                return nil
            }

            return PreferenceStyleInput(
                kind: kind,
                rating: ps.rating,
                orderRecommend: ps.order_recommend,
                isAppealing: ps.isAppealing(),
                isUnappealing: ps.isUnappealing(),
                styleId: ps.style_id,
                styleName: style.name,
                styleImageURL: style.getImage(width: 400, height: 400)
            )
        }

        recomputeAndStoreStats(profile: profileInput, preferenceStyles: prefInputs)
    }
}
