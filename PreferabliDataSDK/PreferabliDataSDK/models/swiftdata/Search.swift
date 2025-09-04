// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Internal class used for tracking searches.
@Model
public final class Search {
    var count: Int
    var last_searched: Date
    var text: String

    init(count: Int, last_searched: Date, text: String) {
        self.count = count
        self.last_searched = last_searched
        self.text = text
    }
    
    internal func getLastSearched() -> Date {
        return last_searched
   }
    
    static internal func sortSearchesByLastSearched(searches: [Search]) -> [Search] {
        return searches.sorted {
            let d1 = $0.getLastSearched()
            let d2 = $1.getLastSearched()
            if d1 == d2 {
                return $0.count > $1.count   // tie-breaker: higher count first
            }
            return d1 > d2                   // newer date first
        }
    }

    static internal func sortSearchesByCount(searches: [Search]) -> [Search] {
        return searches.sorted {
            if $0.count == $1.count {
                let d1 = $0.getLastSearched()
                let d2 = $1.getLastSearched()
                return d1 > d2               // tie-breaker: newer first
            }
            return $0.count > $1.count       // higher count first
        }
    }

}
