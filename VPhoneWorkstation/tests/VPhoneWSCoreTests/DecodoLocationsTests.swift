import Foundation
import Testing
@testable import VPhoneWSCore

@Test func decodoCatalogMatchesDashboardInventoryAndFiltering() throws {
    let data = Data(#"{"static_isp":{"ip_locations":{"US":100,"IN":0,"FR":1},"ip_locations_by_city":{"US":[{"city":"Boston","state":"Massachusetts","count":10},{"city":"New York City","state":"New York","count":10},{"city":"","state":"","count":0},{"city":"Washington","state":"DC","count":0}],"FR":[{"city":"Paris","state":"Ile de France","count":1}],"IN":[{"city":"Mumbai","state":"Maharashtra","count":10}]}}}"#.utf8)
    let items = try DecodoLocations.decode(data)
    #expect(items.filter { $0.kind == .country }.count == 2)
    #expect(items.filter { $0.kind == .state }.count == 2)
    #expect(items.filter { $0.kind == .city }.count == 3)
    #expect(DecodoLocation.filtered(items, kind: nil, search: "Washington").isEmpty)
    #expect(DecodoLocation.filtered(items, kind: .city, search: "YORK").map(\.label) == ["New York City (New York)"])
    #expect(DecodoLocation.filtered(items, kind: nil, search: "Mumbai").isEmpty)
    #expect(DecodoLocation.filtered(items, kind: .state, search: "France").isEmpty)
    #expect(!DecodoLocation.filtered(items, kind: nil, search: "foo").contains(.random))
}

@Test func decodoCatalogSelectionBuildsCountryStateCityAndRandomCredentials() throws {
    let template: [String: Any] = ["server": "isp.decodo.com", "type": "http", "tls": true,
        "username": "user-account-country-us-city-new_york_city", "password": "fixture", "dialer-proxy": "Transit"]
    for (location, suffix) in [
        (DecodoLocation.random, ""),
        (.init(kind: .country, country: "FR", city: "", state: ""), "-country-fr"),
        (.init(kind: .state, country: "US", city: "", state: "New York"), "-country-us-state-new_york"),
        (.init(kind: .city, country: "US", city: "New York City", state: "New York"), "-country-us-city-new_york_city")
    ] {
        let node = try DecodoISP.endpoint(name: "IP · ISP test", template: template, city: "ignored", port: 40000, location: location)
        #expect(node.configuration["username"] as? String == "user-account" + suffix)
        #expect(node.configuration["dialer-proxy"] as? String == "Transit")
    }
    #expect(throws: (any Error).self) { try DecodoLocations.decode(Data("{}".utf8)) }
}
