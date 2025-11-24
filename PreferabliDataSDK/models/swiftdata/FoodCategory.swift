// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
internal final class FoodCategory: HasIntID, HasTimestamps {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var name: String?
    public var icon_url: String?
    
    public init(id: Int) { self.id = id }

    init(id: Int, name: String, icon_url: String? = nil) {
        self.id = id
        self.name = name
        self.icon_url = icon_url
    }
    
    public static func predicate(forID id: Int) -> Predicate<FoodCategory> {
        #Predicate<FoodCategory> { $0.id == id }
    }
    
    static internal func sortFoodCats(foodCats: [FoodCategory]) -> Array<FoodCategory> {
        return foodCats.sorted {
            return String.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }
}

