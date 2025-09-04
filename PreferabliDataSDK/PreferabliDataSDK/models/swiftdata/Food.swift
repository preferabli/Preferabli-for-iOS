// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// You can use foods to get pairings within ``Preferabli/getRecs(product_category:product_type:collection_id:price_min:price_max:style_ids:food_ids:include_merchant_links:onCompletion:onFailure:)``.
@Model
public final class Food: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var name: String?
    public var desc: String?
    public var keywords: String?
    public var food_category_id: Int?
    public var food_category_name: String?
    public var food_category_url: String?

    public init(id: Int) { self.id = id }

    init(id: Int, name: String? = nil, desc: String? = nil, keywords: String? = nil, food_category_id: Int? = nil, food_category_name: String? = nil, food_category_url: String? = nil) {
        self.id = id
        self.name = name
        self.desc = desc
        self.keywords = keywords
        self.food_category_id = food_category_id
        self.food_category_name = food_category_name
        self.food_category_url = food_category_url
    }
    
    /// Sort foods alphabetically.
    /// - Parameter foods: an array of foods to be sorted.
    /// - Returns: a sorted array of foods.
    static public func sortFoodsAlpha(foods: [Food]) -> Array<Food> {
        return foods.sorted {
            return PreferabliTools.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }
    
    /// Filter foods by submitted search terms.
    /// - Parameters:
    ///   - foods: an array of foods to be filtered.
    ///   - search_text: string that contains the search term.
    /// - Returns: a filtered array of foods.
    static public func filterFoods(foods : Array<Food>, search_text : String) -> Array<Food> {
        var filteredFoods = Array<Food>()
        if (search_text.isEmptyOrWhitespace()) {
            filteredFoods = foods
        } else {
            let searchTerms = search_text.components(separatedBy: " ")
            filteredFoods = foods.filter() {
                innerloop:
                    for searchTerm in searchTerms {
                        if ($0.filterFood(search_term: searchTerm)) {
                            continue
                        } else {
                            return false
                        }
                }
                return true
            }
        }
        return filteredFoods
    }
    
    /// Get the food's image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : CGFloat, height : CGFloat, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: food_category_url, width: width, height: height, quality: quality)
    }
    
     internal func filterFood(search_term : String) -> Bool {
        if (search_term.isEmptyOrWhitespace()) {
            return true
        } else if (name?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (keywords?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else {
            return false
        }
    }
}
