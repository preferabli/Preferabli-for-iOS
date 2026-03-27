//
//  Storage+DTOUpserts.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation
import SwiftData

// MARK: - Cancellation helpers
extension Storage {
    /// Upserts are always invoked inside `withBackgroundContext`, `withBackgroundContextAsync`, or `withContext`.
    /// Still, we must cooperate with Task cancellation because logout may be deleting the graph concurrently.
    @inline(__always)
    nonisolated static func checkCancelled() throws {
        try Task.checkCancellation()
    }

    /// Use right before *relationship setters* / collection replacements, which are the hottest crash points
    /// when instances have been invalidated by a wipe.
    @inline(__always)
    nonisolated static func checkCancelledBeforeRelationshipWrite() throws {
        try Task.checkCancellation()
    }
}

extension Storage {

    // MARK: Product

    @discardableResult
    nonisolated static func upsertProduct(from dto: ProductDTO, tempProductId: Int? = nil, in ctx: ModelContext) throws -> Product {

        try checkCancelled()

        let product: Product
        if let pid = tempProductId, let temp = try Storage.fetchById(Product.self, id: pid, in: ctx) {
            product = temp
            product.id = dto.id
        } else {
            product = try fetchOrInsert(Product.self, id: dto.id, in: ctx) { Product(id: dto.id) }
        }

        try checkCancelled()

        product.name = dto.name
        product.created_at = dto.created_at ?? product.created_at
        product.updated_at = dto.updated_at ?? product.updated_at
        product.brand = dto.brand
        product.decant = dto.decant
        product.grape = dto.grape
        product.brand_lat = dto.brand_lat
        product.brand_lon = dto.brand_lon
        product.show_year_dropdown = dto.show_year_dropdown
        product.recommendable = dto.recommendable
        product.region = dto.region
        product.type = dto.type
        product.category = dto.category
        product.subcategory = dto.subcategory
        product.brand_id = dto.brand_id
        product.product_hash = dto.hash
        product.country_code = dto.country_code

        // Primary image
        if let imgDTO = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: imgDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if product.primary_image !== media {
                product.primary_image = media
            }
        }

        // Variants
        var mostRecentYear = product.cachedMostRecentVariant?.year ?? -2
        if let vDTOs = dto.variants {
            for vDTO in vDTOs {
                try checkCancelled()
                let variant = try upsertVariant(from: vDTO, product: product, in: ctx)
                if variant.year > mostRecentYear {
                    mostRecentYear = variant.year

                    try checkCancelledBeforeRelationshipWrite()
                    product.cachedMostRecentVariant = variant
                }
            }
        }

        if let latest = dto.latest_variant_num_dollar_signs, latest != 0 {
            if product.variants.isEmpty {
                try checkCancelled()

                let variant = Variant(id: generateRandomLongId(), year: Variant.CURRENT_VARIANT_YEAR, product: product)
                variant.num_dollar_signs = latest

                try checkCancelledBeforeRelationshipWrite()
                product.cachedMostRecentVariant = variant
                ctx.insert(variant)
            }
        }

        return product
    }

    // MARK: ProductProfile

    @discardableResult
    nonisolated static func upsertProductProfile(
        from dto: ProductProfileDTO,
        for product: Product,
        in ctx: ModelContext
    ) throws -> ProductProfile {

        try checkCancelled()

        let profile = try fetchOrInsert(ProductProfile.self, id: product.id, in: ctx) { ProductProfile(product: product) }

        try checkCancelledBeforeRelationshipWrite()
        profile.product = product
        if product.profile !== profile {
            product.profile = profile
        }

        try checkCancelled()

        profile.refreshed_at = Date()
        profile.trait1Name  = dto.trait1Name
        profile.trait2Name  = dto.trait2Name
        profile.trait3Name  = dto.trait3Name
        profile.trait4Name  = dto.trait4Name
        profile.trait1Level = dto.trait1Level
        profile.trait2Level = dto.trait2Level
        profile.trait3Level = dto.trait3Level
        profile.trait4Level = dto.trait4Level
        profile.flavor1Name = dto.flavor1Name
        profile.flavor2Name = dto.flavor2Name
        profile.flavor3Name = dto.flavor3Name
        profile.flavor4Name = dto.flavor4Name
        profile.flavor1Image = dto.flavor1Image
        profile.flavor2Image = dto.flavor2Image
        profile.flavor3Image = dto.flavor3Image
        profile.flavor4Image = dto.flavor4Image
        profile.food_category_1_name         = dto.food_category_1_name
        profile.food_category_2_name         = dto.food_category_2_name
        profile.food_category_3_name         = dto.food_category_3_name
        profile.food_category_4_name         = dto.food_category_4_name
        profile.food_category_1_icon_png_url = dto.food_category_1_icon_png_url
        profile.food_category_2_icon_png_url = dto.food_category_2_icon_png_url
        profile.food_category_3_icon_png_url = dto.food_category_3_icon_png_url
        profile.food_category_4_icon_png_url = dto.food_category_4_icon_png_url

        return profile
    }

    @discardableResult
    nonisolated static func upsertPreferenceData(
        from dto: PreferenceDataDTO,
        for product: Product,
        in ctx: ModelContext
    ) throws -> PreferenceData {

        try checkCancelled()

        var preference_data = product.preference_data
        if preference_data == nil {
            let created = PreferenceData(product: product)

            try checkCancelledBeforeRelationshipWrite()
            product.preference_data = created

            ctx.insert(created)
            preference_data = created
        }

        let data = preference_data!

        try checkCancelled()

        data.refreshed_at = Date()
        data.title  = dto.title
        data.confidence_code = dto.confidence_code
        data.details = dto.details
        data.formatted_predict_rating = dto.formatted_predict_rating

        return data
    }

    // MARK: Variant

    @discardableResult
    nonisolated static func upsertVariant(from dto: VariantDTO, product: Product, in ctx: ModelContext) throws -> Variant {

        try checkCancelled()

        let v: Variant
        if let temp = product.getVariantWithYear(year: dto.year) {
            v = temp
        } else {
            v = try fetchOrInsert(Variant.self, id: dto.id, in: ctx) {
                Variant(id: dto.id, year: dto.year, product: product)
            }
        }

        try checkCancelled()

        // ✅ Re-assert required fields
        v.id = dto.id
        v.year = dto.year

        try checkCancelledBeforeRelationshipWrite()
        if v.product.id != product.id { v.product = product }

        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.num_dollar_signs = dto.num_dollar_signs ?? v.num_dollar_signs
        v.price = dto.price ?? v.price
        v.recommendable = dto.recommendable ?? v.recommendable

        if let imgDTO = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: imgDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.primary_image !== media { v.primary_image = media }
        }

        return v
    }

    // MARK: Tag

    @discardableResult
    nonisolated static func upsertTag(from dto: TagDTO, variant: Variant, tempTagId: Int? = nil, in ctx: ModelContext) throws -> Tag {

        try checkCancelled()

        let t: Tag
        if let tid = tempTagId, let temp = try Storage.fetchById(Tag.self, id: tid, in: ctx) {
            t = temp
            t.id = dto.id
        } else {
            t = try fetchOrInsert(Tag.self, id: dto.id, in: ctx) { Tag(id: dto.id, collection_id: dto.collection_id, variant: variant) }
        }

        try checkCancelled()

        t.collection_id = dto.collection_id ?? t.collection_id
        t.comment = dto.comment ?? t.comment
        t.created_at = dto.created_at ?? t.created_at
        t.location = dto.location ?? t.location
        t.badge = dto.badge ?? t.badge
        t.tagged_in_collection_id = dto.tagged_in_collection_id ?? t.tagged_in_collection_id
        t.tagged_in_channel_id = dto.tagged_in_channel_id ?? t.tagged_in_channel_id
        t.tagged_in_channel_name = dto.tagged_in_channel_name ?? t.tagged_in_channel_name
        t.type = dto.type ?? t.type
        t.updated_at = dto.updated_at ?? t.updated_at
        t.user_id = dto.user_id ?? t.user_id
        t.value = dto.value ?? t.value
        t.bin = dto.bin ?? t.bin
        t.variant_id = dto.variant_id ?? t.variant_id
        t.quantity = dto.quantity ?? t.quantity
        t.format_ml = dto.format_ml ?? t.format_ml
        t.price = dto.price ?? t.price
        t.customer_id = dto.customer_id ?? t.customer_id

        let product = variant.product
        let newDate = t.created_at ?? .now

        // These are just pointer assignments but still relationship-ish cached refs.
        try checkCancelledBeforeRelationshipWrite()

        if t.isRating() {
            let currentDate = product.cachedMostRecentRating?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedMostRecentRating = t
            }
        } else if t.isWishlist() {
            let currentDate = product.cachedWishlist?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedWishlist = t
            }
        } else if t.tag_type == .COLLECTION, Storage.isCellarCollectionID(t.collection_id) {
            let currentDate = product.cachedCellar?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedCellar = t
            }
        }

        return t
    }

    // MARK: Media

    @discardableResult
    nonisolated static func upsertMedia(from dto: MediaDTO, in ctx: ModelContext) throws -> Media {

        try checkCancelled()

        let m = try fetchOrInsert(Media.self, id: dto.id, in: ctx) { Media(id: dto.id) }
        m.id = dto.id
        m.path = dto.path ?? m.path
        m.created_at = dto.created_at ?? m.created_at
        m.updated_at = dto.updated_at ?? m.updated_at
        m.type = dto.type ?? m.type
        return m
    }

    @discardableResult
    nonisolated static func upsertExperience(from dto: ExperienceDTO, venue: Venue, in ctx: ModelContext) throws -> Experience? {

        try checkCancelled()

        guard let name = dto.name else {
            return nil
        }
        
        let e = try fetchOrInsert(Experience.self, id: dto.id, in: ctx) {
            Experience(id: dto.id, name: name, venue: venue)
        }

        e.created_at = dto.created_at ?? e.created_at
        e.updated_at = dto.updated_at ?? e.updated_at
        e.name = dto.name ?? e.name
        e.desc = dto.description ?? e.desc
        e.primary_inventory_id = dto.primary_inventory_id ?? e.primary_inventory_id
        e.reservations_provider = dto.reservations_provider ?? e.reservations_provider
        e.booking_link = dto.booking_link ?? e.booking_link
        e.discount_code = dto.discount_code ?? e.discount_code

        if let imgs = dto.images {
            try checkCancelled()

            let newImages = try imgs.map { img -> Media in
                try checkCancelled()
                return try upsertMedia(from: img, in: ctx)
            }

            try checkCancelledBeforeRelationshipWrite()
            e.images = newImages
        }

        return e
    }

    // MARK: Venue

    @discardableResult
    nonisolated static func upsertVenue(from dto: VenueDTO, market: Market? = nil, in ctx: ModelContext) throws -> Venue? {

        try checkCancelled()

        guard let name = dto.name else {
            return nil
        }
        
        let v = try fetchOrInsert(Venue.self, id: dto.id, in: ctx) {
            Venue(id: dto.id, name: name)
        }

        // MARK: - Fields
        v.address_l1 = dto.address_l1 ?? v.address_l1
        v.address_l2 = dto.address_l2 ?? v.address_l2
        v.city = dto.city ?? v.city
        v.country = dto.country ?? v.country
        v.display_name = dto.display_name ?? v.display_name
        v.lat = dto.lat ?? v.lat
        v.lon = dto.lon ?? v.lon
        v.primary_inventory_id = dto.primary_inventory_id ?? v.primary_inventory_id
        v.featured_collection_id = dto.featured_collection_id ?? v.featured_collection_id
        v.is_virtual = dto.is_virtual ?? v.is_virtual
        v.phone = dto.phone ?? v.phone
        v.email_address = dto.email_address ?? v.email_address
        v.state = dto.state ?? v.state
        v.url = dto.url ?? v.url
        v.url_facebook = dto.url_facebook ?? v.url_facebook
        v.url_instagram = dto.url_instagram ?? v.url_instagram
        v.url_twitter = dto.url_twitter ?? v.url_twitter
        v.url_youtube = dto.url_youtube ?? v.url_youtube
        v.zip_code = dto.zip_code ?? v.zip_code
        v.notes = dto.notes ?? v.notes
        v.is_partner = dto.is_partner ?? v.is_partner

        // MARK: - Market edge (Venue <-> Market) is source-of-truth handled at the CALL LEVEL.
        // Here we only ensure association when a market is provided.
        if let m = market {
            try checkCancelledBeforeRelationshipWrite()
            if !v.markets.contains(where: { $0.id == m.id }) {
                v.markets.append(m)
            }
        }

        // MARK: - Media pointers
        if let video = dto.video {
            try checkCancelled()
            let media = try upsertMedia(from: video, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.video !== media { v.video = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.video = nil
        }

        if let logo = dto.logo {
            try checkCancelled()
            let media = try upsertMedia(from: logo, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.logo !== media { v.logo = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.logo = nil
        }

        if let primary = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: primary, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.primary_image !== media { v.primary_image = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.primary_image = nil
        }

        // MARK: - Venue <-> MarketTrait (per-venue order) via VenueMarketTrait join rows
        // Source-of-truth for this venue within the provided market scope:
        // - nil: endpoint didn't include market_traits -> leave as-is
        // - [] : explicitly none -> clear join rows for this venue+market scope
        if let venueTraitDTOs = dto.market_traits {

            let resolved: [(order: Int?, trait: MarketTraitDTO)] = venueTraitDTOs.compactMap { row in
                guard let t = row.trait else { return nil }
                return (row.order, t)
            }

            let keepTraitIDs = Set(resolved.map { $0.trait.id })
            let scopeMarketID = market?.id

            // 1) Delete missing join rows for this venue+market scope
            if !v.venue_market_traits.isEmpty {
                for link in v.venue_market_traits {
                    try checkCancelled()

                    // Scope filtering
                    if let mid = scopeMarketID {
                        guard link.market_id == mid else { continue }
                    } else {
                        guard link.market_id == nil else { continue }
                    }

                    if !keepTraitIDs.contains(link.trait_id) {
                        try checkCancelledBeforeRelationshipWrite()
                        ctx.delete(link)
                    }
                }
            }

            // 2) Upsert joins + build new ordered list for this scope
            var newScopedLinks: [VenueMarketTrait] = []
            newScopedLinks.reserveCapacity(resolved.count)

            for (order, traitDTO) in resolved {
                try checkCancelled()

                // Hydrate the trait
                let trait = try fetchOrInsert(MarketTrait.self, id: traitDTO.id, in: ctx) { MarketTrait(id: traitDTO.id) }
                trait.type = traitDTO.type ?? trait.type
                trait.name = traitDTO.name ?? trait.name
                trait.icon_url = traitDTO.icon_url ?? trait.icon_url
                trait.created_at = traitDTO.created_at ?? trait.created_at
                trait.updated_at = traitDTO.updated_at ?? trait.updated_at

                let key = VenueMarketTrait.makeKey(venueID: v.id, marketID: scopeMarketID, traitID: trait.id)

                let link: VenueMarketTrait
                if let existing = try Storage.fetchByKey(VenueMarketTrait.self, key: key, in: ctx) {
                    link = existing
                } else {
                    let created = VenueMarketTrait(key: key, venue: v, trait: trait, market_id: scopeMarketID)
                    ctx.insert(created)
                    link = created
                }

                // Keep denorm + order consistent
                link.order = order
                link.venue_id = v.id
                link.trait_id = trait.id
                link.market_id = scopeMarketID

                // Relationship pointers (non-optional in model)
                try checkCancelledBeforeRelationshipWrite()
                if link.venue.id != v.id { link.venue = v }
                if link.trait.id != trait.id { link.trait = trait }

                newScopedLinks.append(link)
            }

            // 3) Replace v.venue_market_traits for this scope only (preserve other scopes)
            try checkCancelledBeforeRelationshipWrite()
            if let mid = scopeMarketID {
                let preserved = v.venue_market_traits.filter { $0.market_id != mid }
                v.venue_market_traits = preserved + newScopedLinks
            } else {
                let preserved = v.venue_market_traits.filter { $0.market_id != nil }
                v.venue_market_traits = preserved + newScopedLinks
            }
        }

        // MARK: - Relationship lists (source-of-truth as provided by venue DTO)
        if let imgs = dto.images {
            var newImages: [Media] = []
            newImages.reserveCapacity(imgs.count)

            for img in imgs {
                try checkCancelled()
                newImages.append(try upsertMedia(from: img, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.images = newImages
        }

        if let hrs = dto.hours {
            var newHours: [VenueHour] = []
            newHours.reserveCapacity(hrs.count)

            for h in hrs {
                try checkCancelled()
                newHours.append(try upsertVenueHour(from: h, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.hours = newHours
        }

        if let dms = dto.active_delivery_methods {
            var newDms: [DeliveryMethod] = []
            newDms.reserveCapacity(dms.count)

            for dm in dms {
                try checkCancelled()
                newDms.append(try upsertDeliveryMethod(from: dm, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.active_delivery_methods = newDms
        }

        return v
    }
    
    nonisolated static func disassociateVenuesNotInSet(
        keepVenueIDs: Set<Int>,
        from market: Market,
        in ctx: ModelContext
    ) throws {
        try checkCancelled()

        let allVenues = try ctx.fetch(FetchDescriptor<Venue>())

        for v in allVenues {
            try checkCancelled()

            let isInMarket = v.markets.contains(where: { $0.id == market.id })
            if isInMarket && !keepVenueIDs.contains(v.id) {
                try checkCancelledBeforeRelationshipWrite()
                v.markets.removeAll(where: { $0.id == market.id })
            }
        }
    }

    @discardableResult
    nonisolated static func upsertVenueHour(from dto: VenueHourDTO, in ctx: ModelContext) throws -> VenueHour {

        try checkCancelled()

        let h = try fetchOrInsert(VenueHour.self, id: dto.id, in: ctx) { VenueHour(id: dto.id) }
        h.weekday = dto.weekday ?? h.weekday
        h.open_time = dto.open_time ?? h.open_time
        h.close_time = dto.close_time ?? h.close_time
        h.is_closed = dto.is_closed ?? h.is_closed
        return h
    }

    @discardableResult
    nonisolated static func upsertDeliveryMethod(from dto: DeliveryMethodDTO, in ctx: ModelContext) throws -> DeliveryMethod {

        try checkCancelled()

        let d = try fetchOrInsert(DeliveryMethod.self, id: dto.id, in: ctx) { DeliveryMethod(id: dto.id) }
        d.shipping_type = dto.shipping_type ?? d.shipping_type
        d.state_abbreviation = dto.state_abbreviation ?? d.state_abbreviation
        d.state_display_name = dto.state_display_name ?? d.state_display_name
        d.country = dto.country ?? d.country
        d.shipping_cost_note = dto.shipping_cost_note ?? d.shipping_cost_note
        d.shipping_speed_note = dto.shipping_speed_note ?? d.shipping_speed_note
        return d
    }

    // MARK: Collection tree

    @discardableResult
    nonisolated static func upsertCollection(from dto: CollectionDTO, in ctx: ModelContext) throws -> Collection {

        try checkCancelled()

        let c = try fetchOrInsert(Collection.self, id: dto.id, in: ctx) { Collection(id: dto.id) }

        c.channel_id = dto.channel_id ?? c.channel_id
        c.sort_channel_id = dto.sort_channel_id ?? c.sort_channel_id
        c.code = dto.code ?? c.code
        c.desc = dto.description ?? c.desc
        c.end_date = dto.end_date ?? c.end_date
        c.updated_at = dto.updated_at ?? c.updated_at
        c.auto_wili = dto.auto_wili ?? c.auto_wili
        c.is_pinned = dto.is_pinned ?? c.is_pinned
        c.display_time = dto.display_time ?? c.display_time
        c.is_browsable = dto.is_browsable ?? c.is_browsable
        c.is_my_cellar = dto.is_my_cellar ?? c.is_my_cellar
        c.lbs_order = dto.lbs_order ?? c.lbs_order
        c.product_count = dto.product_count ?? c.product_count
        c.name = dto.name ?? c.name
        c.badge_method = dto.badge_method ?? c.badge_method
        c.currency = dto.currency ?? c.currency
        c.timezone = dto.timezone ?? c.timezone
        c.published = dto.published ?? c.published
        c.archived = dto.archived ?? c.archived
        c.display_price = dto.display_price ?? c.display_price
        c.display_quantity = dto.display_quantity ?? c.display_quantity
        c.display_bin = dto.display_bin ?? c.display_bin
        c.has_predict_order = dto.has_predict_order ?? c.has_predict_order
        c.is_randomized = dto.is_randomized ?? c.is_randomized
        c.display_group_headings = dto.display_group_headings ?? c.display_group_headings
        c.is_blind = dto.is_blind ?? c.is_blind
        c.start_date = dto.start_date ?? c.start_date
        c.created_at = dto.created_at ?? c.created_at
        c.venue_id = dto.venue_id ?? c.venue_id
        c.sort_channel_name = dto.sort_channel_name ?? c.sort_channel_name
        c.location_based_recs = dto.location_based_recs ?? c.location_based_recs

        // Primary image (fix duplicated block + handle nil)
        if let img = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: img, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if c.primary_image !== media { c.primary_image = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            c.primary_image = nil
        }

        if let vers = dto.versions {
            var newVers: [CollectionVersion] = []
            newVers.reserveCapacity(vers.count)

            for ver in vers {
                try checkCancelled()
                newVers.append(try upsertCollectionVersion(from: ver, collection: c, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            c.versions = newVers
        }

        return c
    }

    // MARK: - CollectionVersion / CollectionGroup / CollectionOrder

    @discardableResult
    nonisolated static func upsertCollectionVersion(
        from dto: CollectionVersionDTO,
        collection: Collection,
        in ctx: ModelContext
    ) throws -> CollectionVersion {

        try checkCancelled()

        let v = try fetchOrInsert(CollectionVersion.self, id: dto.id, in: ctx) {
            CollectionVersion(id: dto.id, collection: collection)
        }

        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.name       = dto.name       ?? v.name
        v.order      = dto.order      ?? v.order

        try checkCancelledBeforeRelationshipWrite()
        if v.collection.id != collection.id {
            v.collection = collection
        }

        if let groupDTOs = dto.groups {
            var newGroups: [CollectionGroup] = []
            newGroups.reserveCapacity(groupDTOs.count)

            for g in groupDTOs {
                try checkCancelled()
                newGroups.append(try upsertCollectionGroup(from: g, version: v, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.groups = newGroups
        }

        return v
    }

    @discardableResult
    nonisolated static func upsertCollectionGroup(
        from dto: CollectionGroupDTO,
        version: CollectionVersion,
        in ctx: ModelContext
    ) throws -> CollectionGroup {

        try checkCancelled()

        let g = try fetchOrInsert(CollectionGroup.self, id: dto.id, in: ctx) {
            CollectionGroup(id: dto.id, version: version)
        }

        g.created_at      = dto.created_at      ?? g.created_at
        g.updated_at      = dto.updated_at      ?? g.updated_at
        g.name            = dto.name            ?? g.name
        g.order           = dto.order           ?? g.order
        g.orderings_count = dto.orderings_count ?? g.orderings_count

        try checkCancelledBeforeRelationshipWrite()
        if g.version.id != version.id {
            g.version = version
        }

        return g
    }

    @discardableResult
    nonisolated static func upsertCollectionOrder(
        from dto: CollectionOrderDTO,
        group: CollectionGroup,
        tag: Tag,
        in ctx: ModelContext
    ) throws -> CollectionOrder {

        try checkCancelled()

        let o = try fetchOrInsert(CollectionOrder.self, id: dto.id, in: ctx) {
            CollectionOrder(
                id: dto.id,
                tag_id: tag.id,
                order: dto.order ?? 0,
                group: group,
                tag: tag
            )
        }

        o.created_at = dto.created_at ?? o.created_at
        o.updated_at = dto.updated_at ?? o.updated_at
        o.order = dto.order
        
        // inside Storage.upsertCollectionOrder(from:group:tag:in:)
        o.collectionID = group.version.collection.id
        o.groupID      = group.id
        o.productID    = tag.variant.product.id
        o.tagCreatedAt = tag.created_at
        o.tagTypeRaw   = tag.tag_type?.getDatabaseName()
        o.year         = (tag.variant.year > 0) ? tag.variant.year : nil
        o.searchableRaw = tag.searchableContent   // compute once, store once

        try checkCancelledBeforeRelationshipWrite()
        if o.group.id != group.id { o.group = group }
        if o.tag.id != tag.id { o.tag = tag }
        o.tag_id = tag.id

        return o
    }

    @discardableResult
    nonisolated static func upsertCollectionTrait(from dto: CollectionTraitDTO, in ctx: ModelContext) throws -> CollectionTrait {

        try checkCancelled()

        let t = try fetchOrInsert(CollectionTrait.self, id: dto.id, in: ctx) { CollectionTrait(id: dto.id) }
        t.name = dto.name ?? t.name
        t.order = dto.order ?? t.order
        t.restrict_to_ring_it = dto.restrict_to_ring_it ?? t.restrict_to_ring_it
        return t
    }

    // MARK: Profile & ProfileStyle

    @discardableResult
    nonisolated static func upsertProfile(from dto: ProfileDTO, in ctx: ModelContext) throws -> Profile {

        try checkCancelled()

        let p = try fetchOrInsert(Profile.self, id: dto.id, in: ctx) { Profile(id: dto.id) }

        p.user_id = dto.user_id
        p.customer_id = dto.customer_id

        p.score = dto.score
        p.score_red       = dto.score_red
        p.score_white     = dto.score_white
        p.score_rose      = dto.score_rose
        p.score_sparkling = dto.score_sparkling
        p.score_fortified = dto.score_fortified
        p.score_whiskey   = dto.score_whiskey
        p.score_tequila   = dto.score_tequila
        p.score_vodka     = dto.score_vodka
        p.score_gin       = dto.score_gin
        p.score_rum       = dto.score_rum
        p.score_sake      = dto.score_sake
        p.score_cocktail  = dto.score_cocktail
        p.score_beer      = dto.score_beer
        p.score_cheese    = dto.score_cheese

        p.created_at = dto.created_at ?? p.created_at
        p.updated_at = dto.updated_at ?? p.updated_at

        for pStyle in dto.preference_styles {
            try checkCancelled()
            _ = try upsertProfileStyle(from: pStyle, profile: p, in: ctx)
        }

        return p
    }

    @discardableResult
    nonisolated static func upsertProfileStyle(from dto: ProfileStyleDTO, profile: Profile, in ctx: ModelContext) throws -> ProfileStyle {

        try checkCancelled()

        let ps = try fetchOrInsert(ProfileStyle.self, id: dto.id, in: ctx) {
            ProfileStyle(id: dto.id, style_id: dto.style_id)
        }

        ps.conflict = dto.conflict ?? ps.conflict
        ps.order_profile = dto.order_profile ?? ps.order_profile
        ps.order_recommend = dto.order_recommend ?? ps.order_recommend
        ps.rating = dto.rating ?? ps.rating
        ps.strength = dto.strength ?? ps.strength
        ps.style_id = dto.style_id ?? ps.style_id
        ps.recommend = dto.recommend ?? ps.recommend
        ps.refine = dto.refine ?? ps.refine
        ps.keywords = dto.keywords ?? ps.keywords
        ps.created_at = dto.created_at ?? ps.created_at
        ps.updated_at = dto.updated_at ?? ps.updated_at

        try checkCancelledBeforeRelationshipWrite()
        ps.profile = profile

        if let s = dto.style {
            try checkCancelled()
            let style = try upsertStyle(from: s, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            ps.style = style
        }

        return ps
    }

    // MARK: UserCollection

    @discardableResult
    nonisolated static func upsertUserCollection(from dto: UserCollectionDTO, in ctx: ModelContext) throws -> UserCollection {

        try checkCancelled()

        let collection = try upsertCollection(from: dto.collection, in: ctx)
        let uc = try fetchOrInsert(UserCollection.self, id: dto.id, in: ctx) {
            UserCollection(id: dto.id, collection_id: dto.collection_id, collection: collection)
        }

        uc.relationship_type = dto.relationship_type ?? uc.relationship_type
        uc.created_at = dto.created_at ?? uc.created_at
        uc.updated_at = dto.updated_at ?? uc.updated_at

        try checkCancelledBeforeRelationshipWrite()
        if uc.collection.id != collection.id { uc.collection = collection }

        return uc
    }

    // MARK: Food

    @discardableResult
    nonisolated static func upsertFood(from dto: FoodDTO, in ctx: ModelContext) throws -> Food {

        try checkCancelled()

        let f = try fetchOrInsert(Food.self, id: dto.id, in: ctx) { Food(id: dto.id) }
        f.name = dto.name ?? f.name
        f.keywords = dto.keywords ?? f.keywords
        f.created_at = dto.created_at ?? f.created_at
        f.updated_at = dto.updated_at ?? f.updated_at
        return f
    }

    // MARK: - Customer

    @discardableResult
    nonisolated static func upsertCustomer(from dto: CustomerDTO, in ctx: ModelContext) throws -> Customer {

        try checkCancelled()

        let c = try fetchOrInsert(Customer.self, id: dto.id, in: ctx) { Customer(id: dto.id) }
        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at
        c.avatar_url = dto.avatar_url ?? c.avatar_url
        c.merchant_user_email_address = dto.merchant_user_email_address ?? c.merchant_user_email_address
        c.merchant_user_id = dto.merchant_user_id ?? c.merchant_user_id
        c.merchant_user_name = dto.merchant_user_name ?? c.merchant_user_name
        c.merchant_user_display_name = dto.merchant_user_display_name ?? c.merchant_user_display_name
        c.role = dto.role ?? c.role
        return c
    }

    // MARK: - Location

    @discardableResult
    nonisolated static func upsertLocation(from dto: LocationDTO, in ctx: ModelContext) throws -> Location {

        try checkCancelled()

        let l = try fetchOrInsert(Location.self, id: dto.id, in: ctx) { Location(id: dto.id) }
        l.created_at = dto.created_at ?? l.created_at
        l.updated_at = dto.updated_at ?? l.updated_at
        if let lat = dto.latitude { l.latitude = lat }
        if let lon = dto.longitude { l.longitude = lon }
        if let zip = dto.zip_code { l.zip_code = zip }
        return l
    }

    // MARK: - Reservation

    @discardableResult
    nonisolated static func upsertReservation(from dto: ReservationDTO, in ctx: ModelContext) throws -> Reservation {

        try checkCancelled()

        let r = try fetchOrInsert(Reservation.self, id: dto.id, in: ctx) { Reservation(id: dto.id) }
        r.created_at     = dto.created_at ?? r.created_at
        r.updated_at     = dto.updated_at ?? r.updated_at
        r.region         = dto.region ?? r.region
        r.date           = dto.date ?? r.date
        r.title          = dto.title ?? r.title
        r.timeString     = dto.timeString ?? r.timeString
        r.imageURLString = dto.imageURLString ?? r.imageURLString
        return r
    }

    // MARK: - Style

    @discardableResult
    nonisolated static func upsertStyle(from dto: StyleDTO, profile_style: ProfileStyle? = nil, in ctx: ModelContext) throws -> Style {

        try checkCancelled()

        let s = try fetchOrInsert(Style.self, id: dto.id, in: ctx) { Style(id: dto.id, type: dto.type) }

        s.created_at        = dto.created_at ?? s.created_at
        s.updated_at        = dto.updated_at ?? s.updated_at
        s.desc              = dto.description
        s.name              = dto.name
        s.type              = dto.type
        s.primary_image_url = dto.primary_image_url
        s.product_category  = dto.product_category

        // Relationship pointer write
        if let ps = profile_style {
            try checkCancelledBeforeRelationshipWrite()
            ps.style = s
        }

        // Source-of-truth replacement: build then assign
        var newLocations: [Location] = []
        newLocations.reserveCapacity(dto.locations.count)

        for locationDTO in dto.locations {
            try checkCancelled()
            newLocations.append(try upsertLocation(from: locationDTO, in: ctx))
        }

        try checkCancelledBeforeRelationshipWrite()
        s.locations = newLocations

        return s
    }

    // MARK: - FoodCategory

    @discardableResult
    nonisolated static func upsertFoodCategory(from dto: FoodCategoryDTO, in ctx: ModelContext) throws -> FoodCategory {

        try checkCancelled()

        let fc = try fetchOrInsert(FoodCategory.self, id: dto.id, in: ctx) { FoodCategory(id: dto.id) }
        fc.created_at = dto.created_at ?? fc.created_at
        fc.updated_at = dto.updated_at ?? fc.updated_at
        fc.name = dto.name ?? fc.name
        fc.icon_url = dto.icon_url ?? fc.icon_url
        fc.icon_svg_url = dto.icon_svg_url ?? fc.icon_svg_url
        
        return fc
    }

    /// Fetch (or create) a Search row by its `text`. Your model has no `id`.
    private static func fetchSearchByText(_ text: String, in ctx: ModelContext) throws -> Search? {
        var fd = FetchDescriptor<Search>(predicate: #Predicate<Search> { $0.text == text })
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    @discardableResult
    static func upsertSearch(from dto: SearchDTO, in ctx: ModelContext) throws -> Search {

        try checkCancelled()

        if let existing = try fetchSearchByText(dto.text, in: ctx) {
            if let cnt = dto.count { existing.count = cnt }
            if let d = dto.last_searched { existing.last_searched = d }
            return existing
        }

        let new = Search(
            count: dto.count ?? 0,
            last_searched: dto.last_searched ?? Date(),
            text: dto.text
        )
        ctx.insert(new)
        return new
    }

    // MARK: - PreferabliUser

    @discardableResult
    nonisolated static func upsertPreferabliUser(from dto: PreferabliUserDTO, in ctx: ModelContext) throws -> PreferabliUser {

        try checkCancelled()

        let u = try fetchOrInsert(PreferabliUser.self, id: dto.id, in: ctx) { PreferabliUser(id: dto.id) }

        u.created_at = dto.created_at ?? u.created_at
        u.updated_at = dto.updated_at ?? u.updated_at

        u.country = dto.country ?? u.country
        u.display_name = dto.display_name ?? u.display_name
        u.email = dto.email ?? u.email
        u.is_team_preferabli = dto.is_team_preferabli ?? u.is_team_preferabli
        u.fname = dto.fname ?? u.fname
        u.lname = dto.lname ?? u.lname
        u.claim_code = dto.claim_code ?? u.claim_code
        u.has_merchant_access = dto.has_merchant_access ?? u.has_merchant_access
        u.has_kiosks = dto.has_kiosks ?? u.has_kiosks
        u.zip_code = dto.zip_code ?? u.zip_code
        u.intercom_hmac = dto.intercom_hmac ?? u.intercom_hmac
        u.rating_collection_id = dto.rating_collection_id ?? u.rating_collection_id
        u.provided_feedback_at = dto.provided_feedback_at ?? u.provided_feedback_at
        u.wishlist_collection_id = dto.wishlist_collection_id ?? u.wishlist_collection_id
        u.avatar_background_color_hex = dto.avatar_background_color_hex ?? u.avatar_background_color_hex
        u.avatar_text_color_hex = dto.avatar_text_color_hex ?? u.avatar_text_color_hex

        if let avatarDTO = dto.avatar {
            try checkCancelled()
            let media = try upsertMedia(from: avatarDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            u.avatar = media
        } else {
            try checkCancelledBeforeRelationshipWrite()
            u.avatar = nil
        }

        return u
    }

    // MARK: - Channel

    @discardableResult
    nonisolated static func upsertChannel(from dto: ChannelDTO, in ctx: ModelContext) throws -> Channel {

        try checkCancelled()

        let c = try fetchOrInsert(Channel.self, id: dto.id, in: ctx) { Channel(id: dto.id) }

        c.account_id = dto.account_id ?? c.account_id
        c.name = dto.name ?? c.name
        c.description_text = dto.description ?? c.description_text
        c.order = dto.order ?? c.order
        c.archived = dto.archived ?? c.archived
        c.published = dto.published ?? c.published

        c.default_display_vintages = dto.default_display_vintages ?? c.default_display_vintages
        c.default_display_variants = dto.default_display_variants ?? c.default_display_variants
        c.default_display_variant_details = dto.display_variant_details ?? c.default_display_variant_details
        c.default_display_price = dto.default_display_price ?? c.default_display_price
        c.default_display_quantity = dto.default_display_quantity ?? c.default_display_quantity
        c.default_display_bin = dto.default_display_bin ?? c.default_display_bin
        c.default_downweight_previous_recs_duration = dto.default_downweight_previous_recs_duration ?? c.default_downweight_previous_recs_duration

        c.has_download_pdf = dto.has_download_pdf ?? c.has_download_pdf
        c.has_download_csv = dto.has_download_csv ?? c.has_download_csv
        c.has_download_xlsx = dto.has_download_xlsx ?? c.has_download_xlsx

        c.is_retailer = dto.is_retailer ?? c.is_retailer
        c.is_producer = dto.is_producer ?? c.is_producer
        c.is_restaurant = dto.is_restaurant ?? c.is_restaurant
        c.is_hospitality = dto.is_hospitality ?? c.is_hospitality
        c.is_event = dto.is_event ?? c.is_event
        c.is_verified = dto.is_verified ?? c.is_verified

        c.default_timezone = dto.default_timezone ?? c.default_timezone
        c.default_currency = dto.default_currency ?? c.default_currency
        c.default_badge_method = dto.default_badge_method ?? c.default_badge_method

        c.num_dollar_signs_cutoff_1 = dto.num_dollar_signs_cutoff_1 ?? c.num_dollar_signs_cutoff_1
        c.num_dollar_signs_cutoff_2 = dto.num_dollar_signs_cutoff_2 ?? c.num_dollar_signs_cutoff_2
        c.num_dollar_signs_cutoff_3 = dto.num_dollar_signs_cutoff_3 ?? c.num_dollar_signs_cutoff_3
        c.num_dollar_signs_cutoff_4 = dto.num_dollar_signs_cutoff_4 ?? c.num_dollar_signs_cutoff_4
        c.num_dollar_signs_cutoff_5 = dto.num_dollar_signs_cutoff_5 ?? c.num_dollar_signs_cutoff_5

        c.currency_exchange_multiplier_from_foreign_to_usd =
        dto.currency_exchange_multiplier_from_foreign_to_usd ?? c.currency_exchange_multiplier_from_foreign_to_usd

        c.featured_collection_id = dto.featured_collection_id ?? c.featured_collection_id
        c.primary_inventory_id = dto.primary_inventory_id ?? c.primary_inventory_id
        c.primary_questionnaire_id = dto.primary_questionnaire_id ?? c.primary_questionnaire_id
        c.default_curation_batch_id = dto.default_curation_batch_id ?? c.default_curation_batch_id
        c.default_curation_questions_batch_id = dto.default_curation_questions_batch_id ?? c.default_curation_questions_batch_id
        c.max_number_of_venues = dto.max_number_of_venues ?? c.max_number_of_venues

        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at

        if let imgDTO = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: imgDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if c.primary_image !== media { c.primary_image = media }
        }

        if let imgDTOs = dto.images {
            var newImages: [Media] = []
            newImages.reserveCapacity(imgDTOs.count)

            for img in imgDTOs {
                try checkCancelled()
                newImages.append(try upsertMedia(from: img, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            c.images = newImages
        }

        // Join rows: channel_venues (preserve per-edge flags)
        if let joinDTOs = dto.channel_venues {
            var newJoins: [ChannelVenue] = []
            newJoins.reserveCapacity(joinDTOs.count)

            for j in joinDTOs {
                try checkCancelled()

                let cv = try fetchOrInsert(ChannelVenue.self, id: j.id, in: ctx) { ChannelVenue(id: j.id) }

                cv.is_primary = j.is_primary ?? cv.is_primary
                cv.archived = j.archived ?? cv.archived

                try checkCancelledBeforeRelationshipWrite()
                if cv.channel?.id != c.id { cv.channel = c }

                if let vDTO = j.venue {
                    try checkCancelled()
                    let v = try upsertVenue(from: vDTO, in: ctx)

                    try checkCancelledBeforeRelationshipWrite()
                    if cv.venue?.id != v?.id { cv.venue = v }
                }

                newJoins.append(cv)
            }

            try checkCancelledBeforeRelationshipWrite()
            c.channel_venues = newJoins
        }

        return c
    }

    @discardableResult
    nonisolated static func upsertMarketsSourceOfTruth(
        from rootDTOs: [MarketDTO],
        in ctx: ModelContext
    ) throws -> [Market] {

        try checkCancelled()

        // 1) Collect all market IDs in the incoming forest
        var keepMarketIDs = Set<Int>()
        keepMarketIDs.reserveCapacity(rootDTOs.count * 2)

        func collect(_ dto: MarketDTO) throws {
            try checkCancelled()
            keepMarketIDs.insert(dto.id)
            if let submarkets = dto.submarkets {
                for child in submarkets { try collect(child) }
            }
        }

        for dto in rootDTOs { try collect(dto) }

        // 2) Delete any local Markets not in keep set
        try deleteMarketsNotInSet(keepMarketIDs, in: ctx)

        // 3) Upsert the forest (root parent = nil)
        var roots: [Market] = []
        roots.reserveCapacity(rootDTOs.count)

        for dto in rootDTOs {
            try checkCancelled()
            let m = try upsertMarketTreeNodeSourceOfTruth(from: dto, parent: nil, in: ctx)
            roots.append(m)
        }

        return roots
    }

    nonisolated private static func deleteMarketsNotInSet(
        _ keep: Set<Int>,
        in ctx: ModelContext
    ) throws {

        try checkCancelled()

        let all = try ctx.fetch(FetchDescriptor<Market>())

        for m in all {
            try checkCancelled()
            if !keep.contains(m.id) {
                // Deleting while a logout wipe is happening is also a hot point.
                try checkCancelledBeforeRelationshipWrite()
                ctx.delete(m) // cascades to submarkets + traits because of deleteRule
            }
        }
    }

    @discardableResult
    nonisolated private static func upsertMarketTreeNodeSourceOfTruth(
        from dto: MarketDTO,
        parent: Market?,
        in ctx: ModelContext
    ) throws -> Market {

        try checkCancelled()

        let market = try fetchOrInsert(Market.self, id: dto.id, in: ctx) { Market(id: dto.id) }

        try checkCancelled()

        // Fields
        market.name = dto.name ?? market.name
        market.desc = dto.description ?? market.desc
        market.image_url = dto.image_url ?? market.image_url
        market.order = dto.order ?? market.order
        market.country_code = dto.country_code ?? market.country_code
        market.latitude = dto.latitude ?? market.latitude
        market.longitude = dto.longitude ?? market.longitude
        market.top_level = dto.top_level ?? market.top_level
        market.created_at = dto.created_at ?? market.created_at
        market.updated_at = dto.updated_at ?? market.updated_at
        market.default_span_delta = dto.default_span_delta ?? market.default_span_delta

        // Parent
        try checkCancelledBeforeRelationshipWrite()
        if market.parent?.id != parent?.id {
            market.parent = parent
        }

        // Traits: source-of-truth per market
        let assocDTOs = dto.market_trait_associations ?? []
        try upsertMarketTraitsSourceOfTruth(from: assocDTOs, for: market, in: ctx)

        // Children
        let childDTOs = dto.submarkets ?? []
        var newChildren: [Market] = []
        newChildren.reserveCapacity(childDTOs.count)

        for childDTO in childDTOs {
            try checkCancelled()
            let child = try upsertMarketTreeNodeSourceOfTruth(from: childDTO, parent: market, in: ctx)
            newChildren.append(child)
        }

        if !sameIDs(market.submarkets, newChildren) {
            try checkCancelledBeforeRelationshipWrite()
            market.submarkets = newChildren
        }

        return market
    }
    
    @discardableResult
    nonisolated private static func upsertMarketTraitAssociationForVenue(
        from dto: MarketTraitDTO,
        venue: Venue,
        market: Market?,
        in ctx: ModelContext
    ) throws -> MarketTrait {

        try checkCancelled()

        // 1) Hydrate trait
        let t = try fetchOrInsert(MarketTrait.self, id: dto.id, in: ctx) { MarketTrait(id: dto.id) }
        t.type = dto.type ?? t.type
        t.name = dto.name ?? t.name
        t.icon_url = dto.icon_url ?? t.icon_url
        t.created_at = dto.created_at ?? t.created_at
        t.updated_at = dto.updated_at ?? t.updated_at

        // 2) Ensure join row exists (order is not provided by this DTO; keep existing)
        let scopeMarketID = market?.id
        let key = VenueMarketTrait.makeKey(venueID: venue.id, marketID: scopeMarketID, traitID: t.id)

        let link: VenueMarketTrait
        if let existing = try Storage.fetchByKey(VenueMarketTrait.self, key: key, in: ctx) {
            link = existing
        } else {
            let created = VenueMarketTrait(key: key, venue: venue, trait: t, market_id: scopeMarketID)
            ctx.insert(created)
            link = created
        }

        // Re-assert denorms (helps after wipes / partial graph)
        link.venue_id = venue.id
        link.trait_id = t.id
        link.market_id = scopeMarketID

        try checkCancelledBeforeRelationshipWrite()
        if link.venue.id != venue.id { link.venue = venue }
        if link.trait.id != t.id { link.trait = t }

        // Ensure venue list contains it (avoid duplicates)
        try checkCancelledBeforeRelationshipWrite()
        if !venue.venue_market_traits.contains(where: { $0.key == link.key }) {
            venue.venue_market_traits.append(link)
        }

        return t
    }

    /// Source of truth:
    /// - Upsert all MarketTraitAssociation rows in DTO
    /// - Delete any local MarketTraitAssociation linked to this market that isn't in DTO
    nonisolated private static func upsertMarketTraitsSourceOfTruth(
        from assocDTOs: [MarketTraitAssociationDTO],
        for market: Market,
        in ctx: ModelContext
    ) throws {

        try checkCancelled()

        let keepAssociationIDs = Set(assocDTOs.map { $0.id })

        // 1) Delete missing associations for this market
        if !market.traits.isEmpty {
            for existing in market.traits {
                try checkCancelled()
                if !keepAssociationIDs.contains(existing.id) {
                    try checkCancelledBeforeRelationshipWrite()
                    ctx.delete(existing)
                }
            }
        }

        // 2) Upsert / build new ordered list (preserve API order)
        var newAssocs: [MarketTraitAssociation] = []
        newAssocs.reserveCapacity(assocDTOs.count)

        for aDTO in assocDTOs {
            try checkCancelled()

            guard let traitDTO = aDTO.market_trait else { continue }

            // Hydrate trait using *traitDTO.id* (NOT association id)
            let mt = try fetchOrInsert(MarketTrait.self, id: traitDTO.id, in: ctx) { MarketTrait(id: traitDTO.id) }
            mt.type = traitDTO.type ?? mt.type
            mt.name = traitDTO.name ?? mt.name
            mt.icon_url = traitDTO.icon_url ?? mt.icon_url
            mt.created_at = traitDTO.created_at ?? mt.created_at
            mt.updated_at = traitDTO.updated_at ?? mt.updated_at

            // Association row uses *aDTO.id*
            let mta = try fetchOrInsert(MarketTraitAssociation.self, id: aDTO.id, in: ctx) {
                MarketTraitAssociation(id: aDTO.id, market: market, market_trait: mt)
            }

            mta.order = aDTO.order ?? mta.order
            mta.created_at = aDTO.created_at ?? mta.created_at
            mta.updated_at = aDTO.updated_at ?? mta.updated_at

            try checkCancelledBeforeRelationshipWrite()
            if mta.market.id != market.id { mta.market = market }
            if mta.market_trait.id != mt.id { mta.market_trait = mt }

            newAssocs.append(mta)
        }

        if !sameTraitIDs(market.traits, newAssocs) {
            try checkCancelledBeforeRelationshipWrite()
            market.traits = newAssocs
        }
    }

        @discardableResult
        nonisolated static func upsertRecipeGroup(from dto: RecipeGroupDTO, in ctx: ModelContext) throws -> RecipeGroup {

            try checkCancelled()

            let g = try fetchOrInsert(RecipeGroup.self, id: dto.id, in: ctx) { RecipeGroup(id: dto.id) }

            g.created_at = dto.created_at ?? g.created_at
            g.updated_at = dto.updated_at ?? g.updated_at
            g.order = dto.order ?? g.order
            g.internal_notes = dto.internal_notes ?? g.internal_notes
            g.name = dto.name ?? g.name
            g.type = dto.type ?? g.type
            g.icon_svg_url = dto.icon_svg_url ?? g.icon_svg_url
            
            // Primary image
            if let imgDTO = dto.primary_image {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if g.primary_image !== media { g.primary_image = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                g.primary_image = nil
            }

            return g
        }

        // MARK: - Recipe

        @discardableResult
        nonisolated static func upsertRecipe(from dto: RecipeDTO, in ctx: ModelContext) throws -> Recipe {

            try checkCancelled()

            let fc = try upsertFoodCategory(from: dto.food_category, in: ctx)

            let r = try fetchOrInsert(Recipe.self, id: dto.id, in: ctx) { Recipe(id: dto.id, category: fc) }

            r.created_at = dto.created_at ?? r.created_at
            r.updated_at = dto.updated_at ?? r.updated_at
            r.merchant_recipe_id = dto.merchant_recipe_id ?? r.merchant_recipe_id
            r.url = dto.url ?? r.url
            r.primary_image_url = dto.primary_image_url ?? r.primary_image_url
            r.desc = dto.description ?? r.desc
            r.name = dto.name ?? r.name

            if let groupDTOs = dto.recipe_groups {
                var newGroups: [RecipeGroup] = []
                newGroups.reserveCapacity(groupDTOs.count)

                for gDTO in groupDTOs {
                    try checkCancelled()
                    newGroups.append(try upsertRecipeGroup(from: gDTO, in: ctx))
                }

                try checkCancelledBeforeRelationshipWrite()
                r.recipe_groups = newGroups
            }

            return r
        }
    
    @discardableResult
    nonisolated static func upsertProductRecipe(order: Int, recipe: Recipe, product: Product, in ctx: ModelContext) throws -> ProductRecipe {

        try checkCancelled()
        
        let key = ProductRecipe.makeKey(order: order, recipeId: recipe.id, productId: product.id)

        let pr: ProductRecipe
        if let existing = try Storage.fetchByKey(ProductRecipe.self, key: key, in: ctx) {
            pr = existing
        } else {
            let created = ProductRecipe(key: key, order: order, recipe: recipe, product: product)
            ctx.insert(created)
            pr = created
        }

        return pr
    }

        @discardableResult
        nonisolated static func upsertCTABucket(
            from dto: CTABucketDTO,
            section: String,
            market_id: Int?,
            in ctx: ModelContext
        ) throws -> CTABucket {

            try checkCancelled()

            let b = try fetchOrInsert(CTABucket.self, id: dto.id, in: ctx) {
                CTABucket(id: dto.id, section: section)
            }

            try checkCancelled()

            // Required fields
            b.id = dto.id
            b.section = section
            b.market_id = market_id

            // Fields
            b.badge_icon = dto.badge_icon
            b.badge_color_primary = dto.badge_color_primary
            b.badge_color_secondary = dto.badge_color_secondary
            b.order = dto.order
            b.color_secondary = dto.color_secondary
            b.color_primary = dto.color_primary
            b.deeplink_url = dto.deeplink_url
            b.badge_title = dto.badge_title
            b.title = dto.title
            b.desc = dto.description

            b.created_at = dto.created_at ?? b.created_at
            b.updated_at = dto.updated_at ?? b.updated_at

            // Primary image
            if let imgDTO = dto.primary_image {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if b.primary_image !== media { b.primary_image = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                b.primary_image = nil
            }

            return b
        }

        /// Source-of-truth upsert for CTABuckets with scoped deletes.
        ///
        /// - If `scopeMarketId` and `scopeSection` are nil => delete *all* CTAs not in API response.
        /// - If either is set => delete only CTAs matching that scope that are not in API response.
        ///
        /// Returns the IDs that exist after the operation (the keep set).
        @discardableResult
        nonisolated static func upsertCTABucketsSourceOfTruth(
            from responseDTOs: [CTABucketResponseDTO],
            scopeMarketId: Int?,
            scopeSection: String?,
            in ctx: ModelContext
        ) throws -> [Int] {

            try checkCancelled()

            // 1) Flatten + resolve section/market_id per group
            struct Row {
                let dto: CTABucketDTO
                let section: String
                let market_id: Int?
            }

            var rows: [Row] = []
            rows.reserveCapacity(responseDTOs.reduce(0) { $0 + $1.items.count })

            for group in responseDTOs {
                try checkCancelled()

                // Prefer server-provided group values, fall back to scope params, then a safe default
                let resolvedSection = group.section ?? scopeSection ?? "default"
                let resolvedMarketId = group.market_id ?? scopeMarketId

                for item in group.items {
                    rows.append(Row(dto: item, section: resolvedSection, market_id: resolvedMarketId))
                }
            }

            let keepIDs = Set(rows.map { $0.dto.id })

            // 2) Delete anything in-scope that isn't in keepIDs
            try deleteCTABucketsNotInSet(
                keepIDs,
                scopeMarketId: scopeMarketId,
                scopeSection: scopeSection,
                in: ctx
            )

            // 3) Upsert all rows
            for row in rows {
                try checkCancelled()
                _ = try upsertCTABucket(from: row.dto, section: row.section, market_id: row.market_id, in: ctx)
            }

            return Array(keepIDs)
        }

        nonisolated private static func deleteCTABucketsNotInSet(
            _ keep: Set<Int>,
            scopeMarketId: Int?,
            scopeSection: String?,
            in ctx: ModelContext
        ) throws {

            try checkCancelled()

            // Build fetch descriptor based on scope
            let fd: FetchDescriptor<CTABucket>

            switch (scopeMarketId, scopeSection) {
            case (nil, nil):
                fd = FetchDescriptor<CTABucket>() // global
            case let (m?, nil):
                fd = FetchDescriptor(predicate: #Predicate<CTABucket> { $0.market_id == m })
            case let (nil, s?):
                fd = FetchDescriptor(predicate: #Predicate<CTABucket> { $0.section == s })
            case let (m?, s?):
                fd = FetchDescriptor(predicate: #Predicate<CTABucket> { $0.market_id == m && $0.section == s })
            }

            let existing = try ctx.fetch(fd)

            for b in existing {
                try checkCancelled()
                if !keep.contains(b.id) {
                    try checkCancelledBeforeRelationshipWrite()
                    ctx.delete(b)
                }
            }
        }

    nonisolated private static func sameTraitIDs(_ a: [MarketTraitAssociation], _ b: [MarketTraitAssociation]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
    
    
    nonisolated private static func sameIDs(_ a: [Market], _ b: [Market]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
    
}

extension Storage {

    public nonisolated static func saveCellarCollectionIDs(_ cellarIds: [Int]) {
        let set = Set(cellarIds)
        CellarIDCacheStore.shared.set(set)

        Storage.getKeyStore().set(Array(set), forKey: cellarIDsKey)
    }

    public nonisolated static func loadCellarCollectionIDSetCached() -> Set<Int> {
        if !CellarIDCacheStore.shared.isEmpty() {
            return CellarIDCacheStore.shared.get()
        }

        let arr = Storage.getKeyStore().array(forKey: cellarIDsKey) as? [Int] ?? []
        let set = Set(arr)
        CellarIDCacheStore.shared.set(set)
        return set
    }

    public nonisolated static func isCellarCollectionID(_ id: Int) -> Bool {
        if CellarIDCacheStore.shared.contains(id) { return true }
        return loadCellarCollectionIDSetCached().contains(id)
    }
}

private let cellarIDsKey = "cellar_collection_ids_v1"

private final class CellarIDCacheStore: @unchecked Sendable {
    static let shared = CellarIDCacheStore()

    private var set: Set<Int> = []
    private let lock = NSLock()

    func get() -> Set<Int> {
        lock.lock(); defer { lock.unlock() }
        return set
    }

    func set(_ new: Set<Int>) {
        lock.lock(); defer { lock.unlock() }
        set = new
    }

    func contains(_ id: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.contains(id)
    }

    func isEmpty() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.isEmpty
    }
}
