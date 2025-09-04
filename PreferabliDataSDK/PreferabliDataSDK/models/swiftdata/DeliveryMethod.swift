// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Indicates that a ``Venue`` provides a specified delivery method (``ShippingType``).
@Model
public final class DeliveryMethod: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var shipping_type: String?
    public var state_abbreviation: String?
    public var state_display_name: String?
    public var country: String?
    public var shipping_cost_note: String?
    public var shipping_speed_note: String?

    public init(id: Int) { self.id = id }

    public init(
        id: Int,
        shipping_type: String,
        state_abbreviation: String? = nil,
        state_display_name: String? = nil,
        country: String? = nil,
        shipping_cost_note: String? = nil,
        shipping_speed_note: String? = nil
    ) {
        self.id = id
        self.shipping_type = shipping_type
        self.state_abbreviation = state_abbreviation
        self.state_display_name = state_display_name
        self.country = country
        self.shipping_cost_note = shipping_cost_note
        self.shipping_speed_note = shipping_speed_note
    }

    /// Shipping Type of this fulfillment method.
    public var type : ShippingType {
        ShippingType.getShippingTypeBasedOffDatabaseName(value: shipping_type)
    }
}
