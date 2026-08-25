//
//  VenueImage.swift
//  Preferabli
//

import Foundation
import SwiftData

/// A venue-to-media association that preserves the image order returned by the API.
@Model
public final class VenueImage {

    /// Stable unique key because the API does not provide an id for this association.
    /// Format: "venue:<venue-id>|media:<media-id>"
    @Attribute(.unique) public var key: String

    /// Zero-based position in `VenueDTO.images`.
    public var order: Int

    /// Locally marks an association omitted by the latest authoritative venue payload.
    public var isTombstoned: Bool = false

    /// Denormalized ids make key construction and deterministic sorting inexpensive.
    public var venue_id: Int
    public var media_id: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify) public var venue: Venue
    @Relationship(deleteRule: .nullify) public var media: Media

    public init(key: String, order: Int, venue: Venue, media: Media) {
        self.key = key
        self.order = order
        self.venue = venue
        self.venue_id = venue.id
        self.media = media
        self.media_id = media.id
    }

    public static func makeKey(venueID: Int, mediaID: Int) -> String {
        "venue:\(venueID)|media:\(mediaID)"
    }

    public static func predicate(forKey key: String) -> Predicate<VenueImage> {
        #Predicate<VenueImage> { $0.key == key }
    }
}
