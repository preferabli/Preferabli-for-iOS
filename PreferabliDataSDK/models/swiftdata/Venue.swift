//
//  Venue.swift (SwiftData @Model merged with legacy helpers)
//  Preferabli
//
//  NOTE: This file merges the SwiftData @Model with the original helper
//  methods and documentation comments from the legacy Venue class.
//  - Coordinates are `Double?` (better precision than Int/NSNumber).
//  - `links` and the has* flags are transient (computed / session data).
//  - DeliveryMethod and VenueHour are provided as SwiftData @Model types here
//    to keep this file self-contained, with legacy helpers preserved.
//
//  If you already have DeliveryMethod/VenueHour models elsewhere, you can
//  remove/merge the duplicates—signatures match.
//
//  Generated: merged by tool on demand
//

import Foundation
import SwiftData

/// A venue represents the details for a specific location. If returned as part of ``WhereToBuy``, will contain an array of ``MerchantProductLink``s as ``links``.
@Model
public final class Venue: HasIntID, HasTimestamps, HasImage {
    
    @Attribute(.unique) public var id: Int
    @Attribute public var market_ids_cache: [Int] = []
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var address_l1: String?
    public var address_l2: String?
    public var city: String?
    public var country: String?
    public var display_name: String?
    /// Latitude in decimal degrees.
    public var lat: Double?
    /// Longitude in decimal degrees.
    public var lon: Double?
    public var primary_inventory_id: Int?
    public var featured_collection_id: Int?
    public var is_virtual: Bool?
    public var name: String
    public var phone: String?
    public var email_address: String?
    public var state: String?
    public var url: String?
    public var url_facebook: String?
    public var url_instagram: String?
    public var url_twitter: String?
    public var url_youtube: String?
    public var zip_code: String?
    public var notes: String?
    public var is_partner: Bool?
    
    // local only
    public var isTombstoned: Bool = false

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(deleteRule: .nullify) public var logo: Media?
    @Relationship(deleteRule: .nullify) public var video: Media?
    @Relationship(deleteRule: .nullify) public var video_poster: Media?

    @Relationship(deleteRule: .cascade, inverse: \DeliveryMethod.venue) public var active_delivery_methods: [DeliveryMethod] = []
    @Relationship(deleteRule: .cascade) public var images: [Media] = []
    @Relationship(deleteRule: .cascade, inverse: \VenueHour.venue) public var hours: [VenueHour] = []
    @Relationship(deleteRule: .cascade, inverse: \ChannelVenue.venue)
    public var channel_venues: [ChannelVenue] = []
    @Relationship(deleteRule: .cascade, inverse: \Experience.venue)
    public var experiences: [Experience] = []
    @Relationship(deleteRule: .cascade, inverse: \VenueMarketTrait.venue)
    public var venue_market_traits: [VenueMarketTrait] = []
    @Relationship(deleteRule: .nullify, inverse: \Market.venues)
    public var markets: [Market] = []


    /// Available delivery methods for the current user. Call Where to Buy to populate.
    @Transient internal var hasShipping: Bool?
    @Transient internal var hasLocalDelivery: Bool?
    @Transient internal var hasPickup: Bool?
    @Transient internal var hasInPerson: Bool?

    // MARK: - Init
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public init(
        address_l1: String? = nil,
        address_l2: String? = nil,
        city: String? = nil,
        country: String? = nil,
        display_name: String? = nil,
        id: Int,
        lat: Double? = nil,
        lon: Double? = nil,
        primary_inventory_id: Int? = nil,
        featured_collection_id: Int? = nil,
        is_virtual: Bool? = nil,
        name: String,
        phone: String? = nil,
        email_address: String? = nil,
        state: String? = nil,
        url: String? = nil,
        url_facebook: String? = nil,
        url_instagram: String? = nil,
        url_twitter: String? = nil,
        url_youtube: String? = nil,
        zip_code: String? = nil,
        notes: String? = nil,
        collections: [Collection] = [],
        active_delivery_methods: [DeliveryMethod] = [],
        images: [Media] = [],
        hours: [VenueHour] = []
    ) {
        self.address_l1 = address_l1
        self.address_l2 = address_l2
        self.city = city
        self.country = country
        self.id = id
        self.lat = lat
        self.lon = lon
        self.primary_inventory_id = primary_inventory_id
        self.featured_collection_id = featured_collection_id
        self.name = name
        self.phone = phone
        self.email_address = email_address
        self.state = state
        self.url = url
        self.url_facebook = url_facebook
        self.url_instagram = url_instagram
        self.url_twitter = url_twitter
        self.url_youtube = url_youtube
        self.zip_code = zip_code
        self.notes = notes
        self.active_delivery_methods = active_delivery_methods
        self.images = images
        self.hours = hours
    }
    
    @Transient
    public var channel: Channel? {
        if let primary = channel_venues.first(where: { ($0.is_primary ?? false) && !($0.archived ?? false) })?.channel {
            return primary
        }
        return channel_venues.first(where: { !($0.archived ?? false) })?.channel
    }

    // MARK: - Legacy helpers (ported)

    /// Get your distance in miles to the venue.
    /// - Parameters:
    ///   - your_lat: user's latitude as a NSNumber.
    ///   - your_lon: user's longitude as a NSNumber.
    /// - Returns: user's distance to the venue in miles.
    public func getDistanceInMiles(your_lat: NSNumber, your_lon: NSNumber) -> Int? {
        let vLat = lat.map { NSNumber(value: $0) }
        let vLon = lon.map { NSNumber(value: $0) }
        return PreferabliTools.calculateDistanceInMiles(lat1: your_lat, lon1: your_lon, lat2: vLat, lon2: vLon)
    }

    /// Get a formatted return of the address for a specific venue.
    /// - Parameter one_line: pass true if you want the address returned in one line. False returns the address in a multiline format.
    /// - Returns: the venue's full formatted address.
    public func getFormattedAddress(one_line : Bool) -> String {
        var newLine = "\n"
        if one_line { newLine = " | " }
        let firstTwo = (address_l1.isEmptyOrWhitespace ? "" : (address_l1! + newLine))
                    + (address_l2.isEmptyOrWhitespace ? "" : (address_l2! + newLine))
        var third = city.isEmptyOrWhitespace ? "" : (city! + ", ")
        third = third + (state ?? "") + " " + (zip_code ?? "") + (country.isEmptyOrWhitespace ? "" : (newLine + country!))
        return firstTwo + third
    }
    
    public static func predicate(forID id: Int) -> Predicate<Venue> {
        #Predicate<Venue> { $0.id == id }
    }

    /// Get the venue's city and state.
    /// - Returns: city, state, city and state, or a blank string depending on the information available.
    public func getCityState() -> String {
        if (city.isEmptyOrWhitespace && state.isEmptyOrWhitespace) {
            return ""
        } else if (city.isEmptyOrWhitespace) {
            return state ?? ""
        } else if (state.isEmptyOrWhitespace) {
            return city ?? ""
        } else {
            return (city ?? "") + ", " + (state ?? "")
        }
    }

    /// Get the venue's shipping speed.
    /// - Returns: the venue's notes about its shipping speed.
    public func getShippingSpeedNote() -> String? {
        for delivery_method in active_delivery_methods {
            if (delivery_method.type == .SHIPPING) {
                return delivery_method.shipping_speed_note
            }
        }
        return ""
    }

    /// Get the venue's shipping cost.
    /// - Returns: the venue's notes about its shipping cost.
    public func getShippingCostNote() -> String? {
        for delivery_method in active_delivery_methods {
            if (delivery_method.type == .SHIPPING) {
                return delivery_method.shipping_cost_note
            }
        }
        return ""
    }
    
    public func primaryVenueCategoryTrait(in market: Market? = nil) -> MarketTrait? {
        let scopeMarketId = market?.id

        let candidates = venue_market_traits.compactMap { link -> (order: Int, trait: MarketTrait)? in
            // Scope: if market provided, match it; else accept any market
            if let mid = scopeMarketId, link.market_id != mid { return nil }

            guard link.trait.type ?? "" == "venue_category"
            else { return nil }

            // Treat nil order as "very large" so it sorts last
            let ord = link.order ?? Int.max
            return (ord, link.trait)
        }

        return candidates.min(by: { $0.order < $1.order })?.trait
    }
    
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        let imagePath : String?
        if (primary_image == nil) {
            if (images != nil && !images.isEmpty) {
                imagePath = images.first?.path
            } else {
                imagePath = channel?.primary_image?.path
            }
        } else {
            imagePath = primary_image?.path
        }
        
        return PreferabliTools.getImageUrl(image: imagePath, width: width, height: height, quality: quality)
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }

    /// Does the venue offer shipping?
    /// - Returns: true if the venue can ship to the user.
    public func getHasShipping() -> Bool {
        if (hasShipping == nil) { getDeliveryMethods() }
        return hasShipping ?? false
    }

    /// Does the venue offer local delivery?
    /// - Returns: true if the venue can deliver locally to the user.
    public func getHasLocalDelivery() -> Bool {
        if (hasLocalDelivery == nil) { getDeliveryMethods() }
        return hasLocalDelivery ?? false
    }

    /// Does the venue offer local pickup?
    /// - Returns: true if the the user can pickup at the venue.
    public func getHasPickup() -> Bool {
        if (hasPickup == nil) { getDeliveryMethods() }
        return hasPickup ?? false
    }
    
    public func getHasInPerson() -> Bool {
        if (hasInPerson == nil) { getDeliveryMethods() }
        return hasInPerson ?? false
    }

    /// Get the open time for the given day of the week for a venue.
    /// - Parameter weekday: a day of the week.
    /// - Returns: the opening time of the venue if it is available. Returns *nil* if it does not exist.
    public func getOpenTime(weekday : Weekday) -> String? {
        for hour in hours {
            if (hour.day_of_week == weekday) {
                return hour.open_time
            }
        }
        return nil
    }

    /// Get the close time for the given day of the week for a venue.
    /// - Parameter weekday: a day of the week.
    /// - Returns: the closing time of the venue if it is available. Returns *nil* if it does not exist.
    public func getCloseTime(weekday : Weekday) -> String {
        for hour in hours {
            if (hour.day_of_week == weekday) {
                return hour.close_time ?? ""
            }
        }
        return ""
    }

    /// Get whether a venue is closed for the given day of the week.
    /// - Parameter weekday: a day of the week.
    /// - Returns: true if the venue is closed on the given day.
    public func getIsClosed(weekday : Weekday) -> Bool {
        for hour in hours {
            if (hour.day_of_week == weekday) {
                return hour.is_closed ?? true
            }
        }
        return false
    }

    internal func getDeliveryMethods() {
        hasShipping = false
        hasLocalDelivery = false
        hasPickup = false
        hasInPerson = false
        
        for delivery_method in active_delivery_methods {
            if (delivery_method.shipping_type == ShippingType.SHIPPING.getDatabaseName()) {
                hasShipping = true
            } else if (delivery_method.shipping_type == ShippingType.LOCAL_DELIVERY.getDatabaseName()) {
                hasLocalDelivery = true
            } else if (delivery_method.shipping_type == ShippingType.PICKUP.getDatabaseName()) {
                hasPickup = true
            } else if (delivery_method.shipping_type == ShippingType.IN_PERSON.getDatabaseName()) {
                hasInPerson = true
            }
        }
    }
    /// Get the Facebook url for a venue.
    /// - Returns: the full Facebook url of the venue.
    public func getFacebookUrl() -> String { "https://www.facebook.com/" + (url_facebook ?? "") }

    /// Get the Instagram url for a venue.
    /// - Returns: the full Instagram url of the venue.
    public func getInstagramUrl() -> String { "https://www.instagram.com/" + (url_instagram ?? "") }

    /// Get the Twitter url for a venue.
    /// - Returns: the full Twitter url of the venue.
    public func getTwitterUrl() -> String { "https://www.twitter.com/" + (url_twitter ?? "") }

    /// Get the YouTube url for a venue.
    /// - Returns: the full YouTube url of the venue.
    public func getYoutubeUrl() -> String { "https://www.youtube.com/" + (url_youtube ?? "") }

    /// Sort an array of venues by their distance from the user.
    /// - Parameters:
    ///   - venues: an array of venues to be sorted.
    ///   - ascending: true for ascending order. False for descending.
    ///   - your_lat: user's latitude as a NSNumber.
    ///   - your_lon: user's longitude as a NSNumber.
    /// - Returns: a sorted array of venues.
    static public func sortVenuesByDistance(venues: [Venue], ascending : Bool, your_lat: NSNumber, your_lon: NSNumber) -> [Venue] {
        return venues.sorted {
            guard let d0 = $0.getDistanceInMiles(your_lat: your_lat, your_lon: your_lon) else { return false }
            guard let d1 = $1.getDistanceInMiles(your_lat: your_lat, your_lon: your_lon) else { return true }
            if d0 == d1 { return String.alphaSortIgnoreThe(x: $0.name ?? "", y: $1.name ?? "") }
            return ascending ? (d0 < d1) : (d0 > d1)
        }
    }
}

/// Represents a fulfillment method for a ``Venue``. Contained within ``DeliveryMethod``.
public enum ShippingType {
    case SHIPPING
    case LOCAL_DELIVERY
    case PICKUP
    case IN_PERSON

    static internal func getShippingTypeBasedOffDatabaseName(value : String?) -> ShippingType {
        if let v = value {
            switch v {
            case "standard_shipping": return .SHIPPING
            case "local_delivery":    return .LOCAL_DELIVERY
            case "pickup":            return .PICKUP
            case "in-person":         return .IN_PERSON
            default:                  return .SHIPPING
            }
        }
        return .SHIPPING
    }

    internal func getDatabaseName() -> String {
        switch self {
        case .SHIPPING:       return "standard_shipping"
        case .LOCAL_DELIVERY: return "local_delivery"
        case .PICKUP:         return "pickup"
        case .IN_PERSON:      return "in-person"
        }
    }

    public func compare(_ other: ShippingType) -> ComparisonResult {
        return self.getDatabaseName().caseInsensitiveCompare(other.getDatabaseName())
    }
}
