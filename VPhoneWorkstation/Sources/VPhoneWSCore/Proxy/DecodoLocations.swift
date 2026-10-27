import Foundation

public struct DecodoLocation: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case random, country, state, city }
    public let kind: Kind
    public let country: String
    public let city: String
    public let state: String
    public var id: String { "\(kind.rawValue):\(country):\(state):\(city)" }
    public var label: String {
        switch kind {
        case .random: "随机"
        case .country: Locale(identifier: "zh_CN").localizedString(forRegionCode: country) ?? country
        case .state: state
        case .city: country == "US" && !state.isEmpty ? "\(city) (\(state))" : city
        }
    }
    public static let random = DecodoLocation(kind: .random, country: "", city: "", state: "")
    var suffix: String {
        guard kind != .random else { return "" }
        var result = "-country-" + country.lowercased()
        if kind == .state { result += "-state-" + Self.token(state) }
        if kind == .city { result += "-city-" + Self.token(city) }
        return result
    }
    static func token(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: " ", with: "_")
    }
    public static func filtered(_ values: [Self], kind: Kind?, search: String) -> [Self] {
        #if VPHONE_CUSTOM_DECODO_LOCATION_BROWSING
        // Foundation's String.contains("") is false; an empty query means browse all locations.
        if search.isEmpty { return values.filter { kind == nil || $0.kind == kind } }
        #endif
        return values.filter { (kind == nil || $0.kind == kind) &&
            ($0.kind == .random ? search.isEmpty : $0.label.lowercased().contains(search.lowercased())) }
    }
}

public enum DecodoLocations {
    // The dashboard derives this selector from the active product's subscription inventory.
    public static func decode(_ data: Data) throws -> [DecodoLocation] {
        struct Row: Decodable { let city: String; let state: String; let count: Int }
        struct Product: Decodable {
            let ip_locations: [String: Int]
            let ip_locations_by_city: [String: [Row]]
        }
        struct Response: Decodable { let static_isp: Product }
        let product = try JSONDecoder().decode(Response.self, from: data).static_isp
        var countries: [DecodoLocation] = [], states: [DecodoLocation] = [], cities: [DecodoLocation] = []
        for (country, count) in product.ip_locations where count > 0 {
            guard country.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else { continue }
            countries.append(.init(kind: .country, country: country, city: "", state: ""))
            for row in product.ip_locations_by_city[country] ?? [] where row.count > 0 {
                if country == "US", !row.state.trimmingCharacters(in: .whitespaces).isEmpty {
                    states.append(.init(kind: .state, country: country, city: "", state: row.state))
                }
                if !row.city.trimmingCharacters(in: .whitespaces).isEmpty {
                    cities.append(.init(kind: .city, country: country, city: row.city, state: row.state))
                }
            }
        }
        func sorted(_ items: [DecodoLocation]) -> [DecodoLocation] {
            Array(Set(items)).sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        return [.random] + sorted(countries) + sorted(states) + sorted(cities)
    }
    public static func fetch() async throws -> [DecodoLocation] {
        try decode(await DecodoAccountSession.shared.subscriptions())
    }
}
