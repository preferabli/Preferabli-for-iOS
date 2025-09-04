// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
internal final class FoodCategory: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    var name: String?
    var icon_url: String?
    @Relationship(deleteRule: .nullify) var styles: [Style] = []

    public init(id: Int) { self.id = id }

    init(id: Int, name: String, icon_url: String? = nil, styles: [Style] = []) {
        self.id = id
        self.name = name
        self.icon_url = icon_url
        self.styles = styles
    }
    
    static internal func sortFoodCats(foodCats: [FoodCategory]) -> Array<FoodCategory> {
        return foodCats.sorted {
            return PreferabliTools.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }
}

