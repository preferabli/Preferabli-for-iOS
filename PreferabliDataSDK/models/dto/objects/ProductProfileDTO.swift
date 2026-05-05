import Foundation

/// Matches the wire format: [{ "key": "...", "value": "..." }]
public struct ProfilePair: Decodable, Sendable {
    public let key: String
    public let value: String
}

/// Normalized DTO for Product Profile that can be built directly from the array of key/value pairs.
public struct ProductProfileDTO: Decodable, Sendable {
    // Traits
    public var trait1Name: String?
    public var trait2Name: String?
    public var trait3Name: String?
    public var trait4Name: String?

    public var trait1Level: Float?
    public var trait2Level: Float?
    public var trait3Level: Float?
    public var trait4Level: Float?

    // Flavors
    public var flavor1Name: String?
    public var flavor2Name: String?
    public var flavor3Name: String?
    public var flavor4Name: String?

    public var flavor1Image: String?
    public var flavor2Image: String?
    public var flavor3Image: String?
    public var flavor4Image: String?

    // Food categories
    public var food_category_1_name: String?
    public var food_category_2_name: String?
    public var food_category_3_name: String?
    public var food_category_4_name: String?

    public var food_category_1_icon_png_url: String?
    public var food_category_2_icon_png_url: String?
    public var food_category_3_icon_png_url: String?
    public var food_category_4_icon_png_url: String?

    // MARK: - Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let pairs = try container.decode([ProfilePair].self)
        self.init(pairs: pairs)
    }

    // MARK: - Convenience init (mirrors your existing class-based init)

    public init(pairs: [ProfilePair]) {
        // Map trait keys -> (slot, displayName)
        // NOTE: if you want localization, swap the `name` strings with WRTools.getString(string:)
        let traitMap: [String: (slot: Int, name: String)] = [
            // wine
            "acidity_percent":   (1, "acidity"),
            "sweetness_percent": (2, "sweetness"),
            "body_percent":      (3, "body"),
            "oak_percent":       (4, "oak"),
            // spirits
            "peat_percent":      (1, "peat"),
            "agave_percent":     (1, "agave"),
            "smoke_percent":     (3, "smoke"),
            // beer
            "hop_percent":       (1, "hop"),
            "malt_percent":      (4, "malt"),
            "flavor_percent":    (1, "flavor_intensity"),
            "carbonation_percent": (3, "carbonation"),
            "alcohol_percent":   (4, "alcohol"),
            // cheese
            "aromatic_percent":  (2, "aromatic"),
            "savouriness_percent": (3, "savouriness"),
            "firmness_percent":  (4, "firmness"),
            // cocktail
            "complexity_percent":  (3, "complexity")
        ]

        // Temp arrays so we can address by index easily
        var traitNames  = [String?](repeating: nil, count: 4)
        var traitLevels = [Float?](repeating: nil, count: 4)

        var flavorNames  = [String?](repeating: nil, count: 4)
        var flavorImages = [String?](repeating: nil, count: 4)

        var foodNames = [String?](repeating: nil, count: 4)
        var foodIcons = [String?](repeating: nil, count: 4)

        func idx(_ n: Int) -> Int { max(0, min(3, n - 1)) }

        for pair in pairs {
            let key = pair.key
            let val = pair.value

            // Traits
            if let mapping = traitMap[key] {
                let i = idx(mapping.slot)
                traitNames[i] = mapping.name
                traitLevels[i] = Float(val)
                continue
            }

            // Flavors
            if key.hasPrefix("flavor_profile_"), key.hasSuffix("_name") {
                if let n = Int(key.replacingOccurrences(of: "flavor_profile_", with: "")
                                   .replacingOccurrences(of: "_name", with: "")) {
                    flavorNames[idx(n)] = val
                }
                continue
            }
            if key.hasPrefix("flavor_profile_"), key.hasSuffix("_icon_png_4x_url") {
                if let n = Int(key.replacingOccurrences(of: "flavor_profile_", with: "")
                                   .replacingOccurrences(of: "_icon_png_4x_url", with: "")) {
                    flavorImages[idx(n)] = val
                }
                continue
            }

            // Food categories
            if key.hasPrefix("food_category_"), key.hasSuffix("_name") {
                if let n = Int(key.replacingOccurrences(of: "food_category_", with: "")
                                   .replacingOccurrences(of: "_name", with: "")) {
                    foodNames[idx(n)] = val
                }
                continue
            }
            if key.hasPrefix("food_category_"), key.hasSuffix("_icon_png_url") {
                if let n = Int(key.replacingOccurrences(of: "food_category_", with: "")
                                   .replacingOccurrences(of: "_icon_png_url", with: "")) {
                    foodIcons[idx(n)] = val
                }
                continue
            }
        }

        // Assign back to slots
        trait1Name = traitNames[0]; trait2Name = traitNames[1]; trait3Name = traitNames[2]; trait4Name = traitNames[3]
        trait1Level = traitLevels[0]; trait2Level = traitLevels[1]; trait3Level = traitLevels[2]; trait4Level = traitLevels[3]

        flavor1Name = flavorNames[0]; flavor2Name = flavorNames[1]; flavor3Name = flavorNames[2]; flavor4Name = flavorNames[3]
        flavor1Image = flavorImages[0]; flavor2Image = flavorImages[1]; flavor3Image = flavorImages[2]; flavor4Image = flavorImages[3]

        food_category_1_name = foodNames[0]; food_category_2_name = foodNames[1]; food_category_3_name = foodNames[2]; food_category_4_name = foodNames[3]
        food_category_1_icon_png_url = foodIcons[0]; food_category_2_icon_png_url = foodIcons[1]; food_category_3_icon_png_url = foodIcons[2]; food_category_4_icon_png_url = foodIcons[3]
    }
}
