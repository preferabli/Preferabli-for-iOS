// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class FoodCategory: HasIntID, HasTimestamps, HasImage {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var name: String?
    public var icon_url: String?
    
    public init(id: Int) { self.id = id }

    public static func predicate(forID id: Int) -> Predicate<FoodCategory> {
        #Predicate<FoodCategory> { $0.id == id }
    }
    
    static public func sortFoodCats(foodCats: [FoodCategory]) -> Array<FoodCategory> {
        return foodCats.sorted {
            return String.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }
    
    public func getImage(width: Int, height: Int, quality: Int) -> URL? {
        return PreferabliTools.getImageUrl(image: icon_url, width: width, height: height, quality: quality)
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }
}

