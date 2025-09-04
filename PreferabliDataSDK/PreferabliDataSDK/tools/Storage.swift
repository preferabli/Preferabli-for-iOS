//
//  Storage.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 8/29/25.
//  Copyright © 2025 RingIT, Inc,. All rights reserved.
//

//
//  Storage.swift  (actor-based)
//  PreferabliDataSDK
//
//  Converted to actor-based hybrid on request.
//  NOTE: Pure helpers remain static to avoid churn in call sites.
//

import SwiftData
import Foundation

/// Internal class used for interacting with our SwiftData storage.
@MainActor
public enum Storage {
    internal static let storeURL: URL = {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        return dir.appendingPathComponent("PreferabliSDK.sqlite")
    }()

    internal static func makeSchema() -> Schema {
        Schema([
            Customer.self,
            PreferabliUser.self,
            Profile.self,
            ProfileStyle.self,
            Style.self,
            Product.self,
            Variant.self,
            Tag.self,
            Media.self,
            Search.self,
            Venue.self,
            VenueHour.self,
            Collection.self,
            CollectionOrder.self,
            CollectionVersion.self,
            CollectionGroup.self,
            CollectionTrait.self,
            DeliveryMethod.self,
            Food.self,
            FoodCategory.self,
            UserCollection.self,
            Reservation.self,
            Location.self
        ])
    }

    internal static var container: ModelContainer = {
        let cfg = ModelConfiguration(schema: makeSchema(), url: storeURL)
        return try! ModelContainer(for: makeSchema(), configurations: [cfg])
    }()

    // Sync variant
    @inline(__always)
    internal static func withContext<T>(
        _ body: @MainActor (ModelContext) throws -> T
    ) rethrows -> T {
        try body(ModelContext(container))
    }

    // Async variant
    @inline(__always)
    internal static func withContext<T>(
        _ body: @MainActor (ModelContext) async throws -> T
    ) async rethrows -> T {
        try await body(ModelContext(container))
    }

    internal static func reset() {
        let fm = FileManager.default
        let url = storeURL
        let wal = url.deletingPathExtension().appendingPathExtension("sqlite-wal")
        let shm = url.deletingPathExtension().appendingPathExtension("sqlite-shm")
        // Swap to in-memory (drop locks) then delete files
        container = try! ModelContainer(for: makeSchema(), configurations: [ModelConfiguration(schema: makeSchema(), isStoredInMemoryOnly: true)])
        _ = try? fm.removeItem(at: url)
        _ = try? fm.removeItem(at: wal)
        _ = try? fm.removeItem(at: shm)
        // Recreate persisted container
        let cfg = ModelConfiguration(schema: makeSchema(), url: storeURL)
        container = try! ModelContainer(for: makeSchema(), configurations: [cfg])
    }
}

@MainActor
public struct StorageFacade {
    
    @discardableResult
    public func withContext<T>(_ body: (ModelContext) throws -> T) rethrows -> T {
        try Storage.withContext(body)
    }
    
    @discardableResult
    public func withContext<T>(_ body: (ModelContext) async throws -> T) async rethrows -> T {
        try await Storage.withContext(body)
    }
    
    public func reset() { Storage.reset() }
    
    public var container: ModelContainer { Storage.container }
    
    public struct QueriesNamespace {
        /// Products whose `id` is in the given list.
        public func products(withIDs ids: [Int]) -> Predicate<Product> {
            ids.isEmpty
            ? #Predicate { _ in false }
            : #Predicate { p in ids.contains(p.id) }
        }
    }
    
    public struct SortsNamespace {
        public var sortProductsByUpdatedDesc: [SortDescriptor<Product>] {
            [SortDescriptor(\Product.updated_at, order: .reverse)]
        }
    }
    
    public var queries: QueriesNamespace { QueriesNamespace() }
    public var sorts: SortsNamespace { SortsNamespace() }
}

// Generic fetch by id (pure)
extension Storage {
    @inline(__always)
    static internal func fetchById<T: PersistentModel & HasIntID>(_ type: T.Type, id: Int?, in ctx: ModelContext) throws -> T? {
        guard let id else { return nil }
        var fd = FetchDescriptor<T>(predicate: #Predicate<T> { $0.id == id })
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
}

// Coercers / parsing
extension Storage {
    @inline(__always) static internal func parseDate(_ any: Any?) -> Date? {
        guard let any else { return nil }
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let i = any as? Int      { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let d = any as? Double   { return Date(timeIntervalSince1970: d) }
        return nil
    }
    nonisolated(unsafe) static internal func asInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
    nonisolated(unsafe) static internal func asDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    @inline(__always) static internal func asBool(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return Bool(s) }
        return nil
    }
    @inline(__always) static internal func asDecimal(_ v: Any?) -> Decimal? {
        if let d = v as? Decimal { return d }
        if let n = v as? NSNumber { return n.decimalValue }
        if let d = v as? Double { return Decimal(d) }
        if let s = v as? String { return Decimal(string: s) }
        return nil
    }
    @inline(__always) static internal func asString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    @inline(__always) static internal func asDataBase64(_ v: Any?) -> Data? {
        guard let s = v as? String else { return nil }
        return Data(base64Encoded: s)
    }
}

// Relationship resolvers (pure)
extension Storage {
    static internal func resolveMedia(_ any: Any?, in ctx: ModelContext) throws -> Media? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertMedia(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Media.self, id: id, in: ctx) ?? { let x = Media(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveVariant(_ any: Any?, in ctx: ModelContext) throws -> Variant? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertVariant(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Variant.self, id: id, in: ctx) ?? { let x = Variant(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveProduct(_ any: Any?, in ctx: ModelContext) throws -> Product? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertProduct(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Product.self, id: id, in: ctx) ?? { let x = Product(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveVenue(_ any: Any?, in ctx: ModelContext) throws -> Venue? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertVenue(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Venue.self, id: id, in: ctx) ?? { let x = Venue(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveCollection(_ any: Any?, in ctx: ModelContext) throws -> Collection? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertCollection(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Collection.self, id: id, in: ctx) ?? { let x = Collection(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveCollectionVersion(_ any: Any?, in ctx: ModelContext) throws -> CollectionVersion? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertCollectionVersion(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(CollectionVersion.self, id: id, in: ctx) ?? { let x = CollectionVersion(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveCollectionGroup(_ any: Any?, in ctx: ModelContext) throws -> CollectionGroup? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertCollectionGroup(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(CollectionGroup.self, id: id, in: ctx) ?? { let x = CollectionGroup(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveTag(_ any: Any?, in ctx: ModelContext) throws -> Tag? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertTag(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Tag.self, id: id, in: ctx) ?? { let x = Tag(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveStyle(_ any: Any?, in ctx: ModelContext) throws -> Style? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertStyle(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Style.self, id: id, in: ctx) ?? { let x = Style(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
    static internal func resolveProfile(_ any: Any?, in ctx: ModelContext) throws -> Profile? {
        guard let any else { return nil }
        if let dict = any as? [String: Any], let _ = asInt(dict["id"]) {
            return try upsertProfile(from: dict, in: ctx)
        }
        if let id = asInt(any) {
            return try fetchById(Profile.self, id: id, in: ctx) ?? { let x = Profile(id: id); ctx.insert(x); return x }()
        }
        return nil
    }
}

// Upserts (pure, unchanged logic)
extension Storage {
    @discardableResult
    static internal func upsertPreferabliUser(from json: [String: Any], in ctx: ModelContext) throws -> PreferabliUser {
        let id = asInt(json["id"]) ?? { fatalError("PreferabliUser JSON missing id") }()
        let u = try fetchById(PreferabliUser.self, id: id, in: ctx) ?? { let nu = PreferabliUser(id: id); ctx.insert(nu); return nu }()
        if let v = asString(json["email"])       { u.email = v }
        if let v = asString(json["fname"])       { u.fname = v }
        if let v = asString(json["lname"])       { u.lname = v }
        if let v = parseDate(json["created_at"]) { u.created_at = v }
        if let v = parseDate(json["updated_at"]) { u.updated_at = v }
        return u
    }

    @discardableResult
    static internal func upsertCustomer(from json: [String: Any], in ctx: ModelContext) throws -> Customer {
        let id = asInt(json["id"]) ?? { fatalError("Customer JSON missing id") }()
        let c = try fetchById(Customer.self, id: id, in: ctx) ?? { let nc = Customer(id: id); ctx.insert(nc); return nc }()
        if let v = asString(json["merchant_user_email_address"]) { c.merchant_user_email_address = v }
        return c
    }

    @discardableResult
    static internal func upsertMedia(from any: Any, in ctx: ModelContext) throws -> Media {
        let dict: [String: Any]
        if let d = any as? [String: Any] { dict = d }
        else if let id = asInt(any)      { dict = ["id": id] }
        else {
            let tmp = Media(id: Int.random(in: 1...Int.max)); ctx.insert(tmp); return tmp
        }
        let id = asInt(dict["id"]) ?? { fatalError("Media JSON missing id") }()
        let m = try fetchById(Media.self, id: id, in: ctx) ?? { let nm = Media(id: id); ctx.insert(nm); return nm }()
        if let v = asString(dict["path"])        { m.path = v }
        if let v = parseDate(dict["created_at"]) { m.created_at = v }
        if let v = parseDate(dict["updated_at"]) { m.updated_at = v }
        if let v = asString(dict["type"])        { m.type = v }
        return m
    }

    @discardableResult
    static internal func upsertTag(from json: [String: Any], in ctx: ModelContext) throws -> Tag {
        let id = asInt(json["id"]) ?? Int.random(in: 1...Int.max)
        let t = try fetchById(Tag.self, id: id, in: ctx) ?? { let nt = Tag(id: id); ctx.insert(nt); return nt }()
        if let v = asInt(json["collection_id"])            { t.collection_id = v }
        if let v = asString(json["comment"])               { t.comment = v }
        if let v = parseDate(json["created_at"])           { t.created_at = v }
        if let v = asString(json["location"])              { t.location = v }
        if let v = asString(json["badge"])                 { t.badge = v }
        if let v = asInt(json["tagged_in_collection_id"])  { t.tagged_in_collection_id = v }
        if let v = asInt(json["tagged_in_channel_id"])     { t.tagged_in_channel_id = v }
        if let v = asString(json["tagged_in_channel_name"]){ t.tagged_in_channel_name = v }
        if let v = asString(json["type"])                  { t.type = v }
        if let v = parseDate(json["updated_at"])           { t.updated_at = v }
        if let v = asInt(json["user_id"])                  { t.user_id = v }
        if let v = asString(json["value"])                 { t.value = v }
        if let v = asString(json["bin"])                   { t.bin = v }
        if let v = asInt(json["variant_id"])               { t.variant_id = v }
        if let v = asInt(json["product_id"])               { t.product_id = v }
        if let v = asInt(json["quantity"])                 { t.quantity = v }
        if let v = asInt(json["format_ml"])                { t.format_ml = v }
        if let v = asDecimal(json["price"])                { t.price = v }
        if let v = asInt(json["customer_id"])              { t.customer_id = v }
        if let rel = try resolveVariant(json["variant"], in: ctx) { t.variant = rel }
        if let arr = json["orderings"] as? [[String: Any]] {
            // When/if you wire up orderings here, keep the one-pass style:
            // t.orderings = try arr.map { try upsertCollectionOrder(from: $0, in: ctx) }
            t.orderings = t.orderings
        }
        return t
    }

    @discardableResult
    static internal func upsertVariant(from json: [String: Any], product: Product? = nil, in ctx: ModelContext) throws -> Variant {
        let id = asInt(json["id"]) ?? { fatalError("Variant JSON missing id") }()
        let v  = try fetchById(Variant.self, id: id, in: ctx) ?? { let nv = Variant(id: id); ctx.insert(nv); return nv }()
        if let d = parseDate(json["created_at"])   { v.created_at = d }
        if let b = asBool(json["fresh"])           { v.fresh = b }
        if let n = asInt(json["num_dollar_signs"]) { v.num_dollar_signs = n }
        if let p = asDecimal(json["price"])        { v.price = p }
        if let b = asBool(json["recommendable"])   { v.recommendable = b }
        if let d = parseDate(json["updated_at"])   { v.updated_at = d }
        if let y = asInt(json["year"])             { v.year = y }
        if let p = product { v.product = p }
        else if let pjson = json["product"] { v.product = try resolveProduct(pjson, in: ctx) ?? v.product }
        if let mi = try resolveMedia(json["primary_image"], in: ctx) { v.primary_image = mi }
        if let tagDicts = json["tags"] as? [[String: Any]] {
            v.tags = try tagDicts.map { try upsertTag(from: $0, in: ctx) }
            for t in v.tags { t.variant = v }
        }
        return v
    }

    @discardableResult
    static internal func upsertProduct(from json: [String: Any], in ctx: ModelContext) throws -> Product {
        let id = asInt(json["id"]) ?? { fatalError("Product JSON missing id") }()
        let p  = try fetchById(Product.self, id: id, in: ctx) ?? { let np = Product(id: id); ctx.insert(np); return np }()
        if let v = asString(json["brand"])           { p.brand = v }
        if let d = parseDate(json["created_at"])     { p.created_at = d }
        if let b = asBool(json["decant"])            { p.decant = b }
        if let v = asString(json["grape"])           { p.grape = v }
        if let v = asInt(json["brand_lat"])          { p.brand_lat = v }
        if let v = asInt(json["brand_lon"])          { p.brand_lon = v }
        if let b = asBool(json["show_year_dropdown"]){ p.show_year_dropdown = b }
        if let v = asString(json["name"])            { p.name = v }
        if let v = asString(json["region"])          { p.region = v }
        if let v = asString(json["type"])            { p.type = v }
        if let v = asString(json["category"])        { p.category = v }
        if let v = asString(json["subcategory"])     { p.subcategory = v }
        if let d = parseDate(json["updated_at"])     { p.updated_at = d }
        if let v = asInt(json["brand_id"])           { p.brand_id = v }
        if let v = asString(json["producthash"])     { p.producthash = v }
        if let mi = try resolveMedia(json["primary_image"], in: ctx) { p.primaryImage = mi }
        if let varr = json["variants"] as? [[String: Any]] {
            p.variants = try varr.map { try upsertVariant(from: $0, product: p, in: ctx) }
            for v in p.variants { v.product = p }
        }
        return p
    }

    @discardableResult
    static internal func upsertUserCollection(from json: [String: Any], in ctx: ModelContext) throws -> UserCollection {
        let id = asInt(json["id"]) ?? { fatalError("UserCollection JSON missing id") }()
        let uc = try fetchById(UserCollection.self, id: id, in: ctx) ?? { let x = UserCollection(id: id); ctx.insert(x); return x }()
        if let v = asString(json["relationship_type"]) { uc.relationship_type = v }
        if let v = asInt(json["collection_id"])        { uc.collection_id = v }
        if let v = parseDate(json["created_at"])       { uc.created_at = v }
        if let v = parseDate(json["updated_at"])       { uc.updated_at = v }
        if let cdict = json["collection"] as? [String: Any] {
            let c = try upsertCollection(from: cdict, in: ctx); uc.collection = c
        } else if let cid = asInt(json["collection_id"]) {
            if let c = try fetchById(Collection.self, id: cid, in: ctx) { uc.collection = c }
            else { let c = Collection(id: cid); ctx.insert(c); uc.collection = c }
        }
        return uc
    }

    @discardableResult
    static internal func upsertVenue(from json: [String: Any], in ctx: ModelContext) throws -> Venue {
        let id = asInt(json["id"]) ?? { fatalError("Venue JSON missing id") }()
        let v  = try fetchById(Venue.self, id: id, in: ctx) ?? { let x = Venue(id: id); ctx.insert(x); return x }()
        if let s = asString(json["address_l1"])          { v.address_l1 = s }
        if let s = asString(json["address_l2"])          { v.address_l2 = s }
        if let s = asString(json["city"])                { v.city = s }
        if let s = asString(json["country"])             { v.country = s }
        if let s = asString(json["display_name"])        { v.display_name = s }
        if let d = asDouble(json["lat"])                 { v.lat = d }
        if let d = asDouble(json["lon"])                 { v.lon = d }
        if let i = asInt(json["primary_inventory_id"])   { v.primary_inventory_id = i }
        if let i = asInt(json["featured_collection_id"]) { v.featured_collection_id = i }
        if let b = asBool(json["is_virtual"])            { v.is_virtual = b }
        if let s = asString(json["name"])                { v.name = s }
        if let s = asString(json["phone"])               { v.phone = s }
        if let s = asString(json["email_address"])       { v.email_address = s }
        if let s = asString(json["state"])               { v.state = s }
        if let s = asString(json["url"])                 { v.url = s }
        if let s = asString(json["url_facebook"])        { v.url_facebook = s }
        if let s = asString(json["url_instagram"])       { v.url_instagram = s }
        if let s = asString(json["url_twitter"])         { v.url_twitter = s }
        if let s = asString(json["url_youtube"])         { v.url_youtube = s }
        if let s = asString(json["zip_code"])            { v.zip_code = s }
        if let s = asString(json["notes"])               { v.notes = s }
        if let arr = json["collections"] as? [[String: Any]]        { v.collections = try arr.map { try upsertCollection(from: $0, in: ctx) } }
        if let arr = json["active_delivery_methods"] as? [[String: Any]] { v.active_delivery_methods = try arr.map { try upsertDeliveryMethod(from: $0, in: ctx) } }
        if let arr = json["images"] as? [[String: Any]]             { v.images = try arr.map { try upsertMedia(from: $0, in: ctx) } }
        if let arr = json["hours"] as? [[String: Any]]              { v.hours = try arr.map { try upsertVenueHour(from: $0, in: ctx) } }
        return v
    }

    @discardableResult
    static internal func upsertDeliveryMethod(from json: [String: Any], in ctx: ModelContext) throws -> DeliveryMethod {
        let id = asInt(json["id"]) ?? { fatalError("DeliveryMethod JSON missing id") }()
        let d  = try fetchById(DeliveryMethod.self, id: id, in: ctx) ?? { let nd = DeliveryMethod(id: id, shipping_type: ""); ctx.insert(nd); return nd }()
        if let s = asString(json["shipping_type"])       { d.shipping_type = s }
        if let s = asString(json["state_abbreviation"])  { d.state_abbreviation = s }
        if let s = asString(json["state_display_name"])  { d.state_display_name = s }
        if let s = asString(json["country"])             { d.country = s }
        if let s = asString(json["shipping_cost_note"])  { d.shipping_cost_note = s }
        if let s = asString(json["shipping_speed_note"]) { d.shipping_speed_note = s }
        return d
    }

    @discardableResult
    static internal func upsertVenueHour(from json: [String: Any], in ctx: ModelContext) throws -> VenueHour {
        let id = asInt(json["id"]) ?? { fatalError("VenueHour JSON missing id") }()
        let h  = try fetchById(VenueHour.self, id: id, in: ctx) ?? { let nh = VenueHour(id: id, is_closed: false); ctx.insert(nh); return nh }()
        if let s = asString(json["weekday"])   { h.weekday = s }
        if let s = asString(json["open_time"]) { h.open_time = s }
        if let s = asString(json["close_time"]){ h.close_time = s }
        if let b = asBool(json["is_closed"])   { h.is_closed = b }
        return h
    }

    @discardableResult
    static internal func upsertCollection(from json: [String: Any], in ctx: ModelContext) throws -> Collection {
        let id = asInt(json["id"]) ?? { fatalError("Collection JSON missing id") }()
        let c  = try fetchById(Collection.self, id: id, in: ctx) ?? { let x = Collection(id: id); ctx.insert(x); return x }()
        if let i = asInt(json["channel_id"])           { c.channel_id = i }
        if let i = asInt(json["sort_channel_id"])      { c.sort_channel_id = i }
        if let s = asString(json["code"])              { c.code = s }
        if let s = asString(json["desc"])              { c.desc = s }
        if let d = parseDate(json["end_date"])         { c.end_date = d }
        if let d = parseDate(json["updated_at"])       { c.updated_at = d }
        if let b = asBool(json["auto_wili"])           { c.auto_wili = b }
        if let b = asBool(json["has_image"])           { c.has_image = b }
        if let b = asBool(json["is_pinned"])           { c.is_pinned = b }
        if let b = asBool(json["display_time"])        { c.display_time = b }
        if let b = asBool(json["is_browsable"])        { c.is_browsable = b }
        if let b = asBool(json["is_my_cellar"])        { c.is_my_cellar = b }
        if let i = asInt(json["lbs_order"])            { c.lbs_order = i }
        if let i = asInt(json["product_count"])        { c.product_count = i }
        if let s = asString(json["name"])              { c.name = s }
        if let s = asString(json["badge_method"])      { c.badge_method = s }
        if let s = asString(json["currency"])          { c.currency = s }
        if let s = asString(json["timezone"])          { c.timezone = s }
        if let b = asBool(json["published"])           { c.published = b }
        if let b = asBool(json["archived"])            { c.archived = b }
        if let b = asBool(json["display_price"])       { c.display_price = b }
        if let b = asBool(json["display_quantity"])    { c.display_quantity = b }
        if let b = asBool(json["display_bin"])         { c.display_bin = b }
        if let b = asBool(json["has_predict_order"])   { c.has_predict_order = b }
        if let b = asBool(json["is_randomized"])       { c.is_randomized = b }
        if let b = asBool(json["display_group_headings"]) { c.display_group_headings = b }
        if let b = asBool(json["is_blind"])            { c.is_blind = b }
        if let d = parseDate(json["start_date"])       { c.start_date = d }
        if let d = parseDate(json["created_at"])       { c.created_at = d }
        if let i = asInt(json["venue_id"])             { c.venue_id = i }
        if let s = asString(json["sort_channel_name"]) { c.sort_channel_name = s }
        if let b = asBool(json["location_based_recs"]) { c.location_based_recs = b }
        if let img = try resolveMedia(json["primary_image"], in: ctx) { c.primary_image = img }
        if let v   = try resolveVenue(json["venue"], in: ctx)         { c.venue = v }
        if let arr = json["versions"] as? [[String: Any]]             { c.versions = try arr.map { try upsertCollectionVersion(from: $0, in: ctx) } }
        if let arr = json["traits"] as? [[String: Any]]               { c.traits   = try arr.map { try upsertCollectionTrait(from: $0, in: ctx) } }
        return c
    }

    @discardableResult
    static internal func upsertCollectionVersion(from json: [String: Any], in ctx: ModelContext) throws -> CollectionVersion {
        let id = asInt(json["id"]) ?? { fatalError("CollectionVersion JSON missing id") }()
        let cv = try fetchById(CollectionVersion.self, id: id, in: ctx) ?? { let x = CollectionVersion(id: id); ctx.insert(x); return x }()
        if let s = asString(json["name"])  { cv.name = s }
        if let i = asInt(json["order"])    { cv.order = i }
        if let rel = try resolveCollection(json["collection"], in: ctx) { cv.collection = rel }
        if let arr = json["groups"] as? [[String: Any]]                 { cv.groups = try arr.map { try upsertCollectionGroup(from: $0, in: ctx) } }
        return cv
    }

    @discardableResult
    static internal func upsertCollectionOrder(from json: [String: Any], in ctx: ModelContext) throws -> CollectionOrder {
        let id = asInt(json["id"]) ?? { fatalError("CollectionOrder JSON missing id") }()
        let o  = try fetchById(CollectionOrder.self, id: id, in: ctx) ?? { let x = CollectionOrder(id: id); ctx.insert(x); return x }()
        if let i = asInt(json["tag_id"])   { o.tag_id = i }
        if let i = asInt(json["order"])    { o.order   = i }
        if let i = asInt(json["group_id"]) { o.group_id = i }
        if let g = try resolveCollectionGroup(json["group"], in: ctx) { o.group = g }
        if let t = try resolveTag(json["tag"], in: ctx)               { o.tag = t }
        return o
    }

    @discardableResult
    static internal func upsertCollectionTrait(from json: [String: Any], in ctx: ModelContext) throws -> CollectionTrait {
        let id = asInt(json["id"]) ?? { fatalError("CollectionTrait JSON missing id") }()
        let t  = try fetchById(CollectionTrait.self, id: id, in: ctx) ?? { let x = CollectionTrait(id: id); ctx.insert(x); return x }()
        if let s = asString(json["name"]) { t.name = s }
        if let i = asInt(json["order"])   { t.order = i }
        if let b = asBool(json["restrict_to_ring_it"]) { t.restrict_to_ring_it = b }
        if let c = try resolveCollection(json["collection"], in: ctx) { t.collection = c }
        return t
    }

    @discardableResult
    static internal func upsertCollectionGroup(from json: [String: Any], in ctx: ModelContext) throws -> CollectionGroup {
        let id = asInt(json["id"]) ?? { fatalError("CollectionGroup JSON missing id") }()
        let g  = try fetchById(CollectionGroup.self, id: id, in: ctx) ?? { let x = CollectionGroup(id: id); ctx.insert(x); return x }()
        if let s = asString(json["name"])         { g.name = s }
        if let i = asInt(json["order"])           { g.order = i }
        if let i = asInt(json["orderings_count"]) { g.orderings_count = i }
        if let rel = try resolveCollectionVersion(json["version"], in: ctx) { g.version = rel }
        if let arr = json["orderings"] as? [[String: Any]]                  { g.orderings = try arr.map { try upsertCollectionOrder(from: $0, in: ctx) } }
        return g
    }

    @discardableResult
    static internal func upsertProfileStyle(from json: [String: Any], in ctx: ModelContext) throws -> ProfileStyle {
        let id = asInt(json["id"]) ?? { fatalError("ProfileStyle JSON missing id") }()
        let ps = try fetchById(ProfileStyle.self, id: id, in: ctx) ?? { let x = ProfileStyle(id: id); ctx.insert(x); return x }()
        if let b = asBool(json["conflict"])         { ps.conflict = b }
        if let i = asInt(json["order_profile"])     { ps.order_profile = i }
        if let i = asInt(json["order_recommend"])   { ps.order_recommend = i }
        if let i = asInt(json["rating"])            { ps.rating = i }
        if let i = asInt(json["strength"])          { ps.strength = i }
        if let i = asInt(json["style_id"])          { ps.style_id = i }
        if let b = asBool(json["recommend"])        { ps.recommend = b }
        if let b = asBool(json["refine"])           { ps.refine = b }
        if let s = asString(json["keywords"])       { ps.keywords = s }
        if let d = parseDate(json["created_at"])    { ps.created_at = d }
        if let d = parseDate(json["updated_at"])    { ps.updated_at = d }
        if let st = try resolveStyle(json["style"], in: ctx)     { ps.style = st }
        if let pr = try resolveProfile(json["profile"], in: ctx) { ps.profile = pr }
        return ps
    }

    @discardableResult
    static internal func upsertStyle(from json: [String: Any], in ctx: ModelContext) throws -> Style {
        let id = asInt(json["id"]) ?? { fatalError("Style JSON missing id") }()
        let s  = try fetchById(Style.self, id: id, in: ctx) ?? { let x = Style(id: id); ctx.insert(x); return x }()
        // add field assignments when Style’s properties are finalized
        return s
    }

    @discardableResult
    static internal func upsertProfile(from json: [String: Any], in ctx: ModelContext) throws -> Profile {
        let id = asInt(json["id"]) ?? { fatalError("Profile JSON missing id") }()
        let p  = try fetchById(Profile.self, id: id, in: ctx) ?? { let x = Profile(id: id); ctx.insert(x); return x }()
        // add field assignments when Profile’s properties are finalized
        return p
    }

    @discardableResult
    static internal func upsertFood(from json: [String: Any], in ctx: ModelContext) throws -> Food {
        let id = asInt(json["id"]) ?? { fatalError("Food JSON missing id") }()
        let f  = try fetchById(Food.self, id: id, in: ctx) ?? { let x = Food(id: id); ctx.insert(x); return x }()
        if let v = asString(json["name"])        { f.name = v }
        if let v = asString(json["keywords"])    { f.keywords = v }
        if let d = parseDate(json["created_at"]) { f.created_at = d }
        if let d = parseDate(json["updated_at"]) { f.updated_at = d }
        return f
    }
}
