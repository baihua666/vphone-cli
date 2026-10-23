import Foundation
import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelURLParameterTests {
    @Test func managedParametersReplaceBaseValuesAndPreserveUnmanagedQuery() throws {
        let result = try VPhoneFlywheelWebPage.url("https://business.example/?keep=1+2&tag=old&tag=older&off=old&ip=stale#section",
            ip: "23.24.25.26", parameters: [
                .init(name: "tag", value: "first"), .init(name: "tag", value: "second"),
                .init(isEnabled: false, name: "tag", value: "hidden"),
                .init(isEnabled: false, name: "off", value: "hidden"),
            ])
        #expect(result == "https://business.example/?keep=1+2&ip=23.24.25.26&tag=first&tag=second#section")
    }

    @Test func customNamesAndValuesAreEncodedWithoutCreatingExtraParameters() throws {
        let name = " 中文&=+# "
        let value = " 中文 + & = % # ? /\n"
        let result = try VPhoneFlywheelWebPage.url("https://business.example/", ip: nil,
            parameters: [.init(name: name, value: value), .init(name: "empty", value: "")])
        let items = try #require(URLComponents(string: result)?.queryItems)
        #expect(items == [URLQueryItem(name: "中文&=+#", value: value), .init(name: "empty", value: "")])
        #expect(!result.contains("+"))
        #expect(result.contains("%2B"))
        #expect(result.hasSuffix("&empty="))
    }

    @Test func deletingRenamingAndUncheckingRowsChangesNextURL() throws {
        var rows: [VPhoneFlywheelURLParameter] = [.init(name: "a", value: "one"), .init(name: "b", value: "two")]
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/", ip: nil, parameters: rows)
                == "https://business.example/?a=one&b=two")
        rows.removeFirst()
        rows[0].name = "renamed"
        rows[0].value = "edited"
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/", ip: nil, parameters: rows)
                == "https://business.example/?renamed=edited")
        rows[0].isEnabled = false
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/?renamed=old#section", ip: nil, parameters: rows)
                == "https://business.example/#section")
    }

    @Test func blankDraftsAreIgnoredAndAutomaticIPCannotBeOverridden() throws {
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/", ip: nil,
            parameters: [.init(), .init(isEnabled: false, name: " ", value: "draft")]) == "https://business.example/")
        for enabled in [true, false] {
            #expect(throws: VPhoneFlywheelError.self) {
                try VPhoneFlywheelWebPage.url("https://business.example/", ip: "23.24.25.26",
                    parameters: [.init(isEnabled: enabled, name: " ip ", value: "manual")])
            }
        }
    }

    @Test func invalidRowFailsBeforeAnyGuestOrNetworkRequest() async {
        for row: VPhoneFlywheelURLParameter in [.init(name: "", value: "missing name"), .init(name: "ip", value: "manual")] {
            var requested = false
            await #expect(throws: VPhoneFlywheelError.self) {
                try await VPhoneFlywheelWebPage.open("https://business.example/", parameters: [row], route: {
                    requested = true
                    return .init(identity: "unused", endpoint: "isp.decodo.com:10001")
                }, rpc: { _, _, _ in requested = true; return [:] })
            }
            #expect(!requested)
        }
    }

    @Test func storeSavesEveryEditAndReopensWithoutChangingExistingPreferences() throws {
        let suite = "FlywheelParameterTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: VPhoneFlywheelWebPage.includeIPPreferenceKey)
        defaults.set("https://business.example/", forKey: VPhoneFlywheelWebPage.urlPreferenceKey)
        let store = VPhoneFlywheelURLParameterStore(defaults: defaults)
        #expect(store.parameters.isEmpty && store.error == nil)
        #expect(defaults.object(forKey: VPhoneFlywheelURLParameterStore.preferenceKey) == nil)
        store.parameters.append(.init(name: "name", value: "中文+&"))
        let id = store.parameters[0].id
        #expect(VPhoneFlywheelURLParameterStore(defaults: defaults).parameters == store.parameters)
        store.parameters[0].name = "renamed"
        store.parameters[0].value = "edited"
        store.parameters[0].isEnabled = false
        let reopened = VPhoneFlywheelURLParameterStore(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(reopened.parameters == [.init(id: id, isEnabled: false, name: "renamed", value: "edited")])
        store.parameters.removeAll()
        #expect(VPhoneFlywheelURLParameterStore(defaults: defaults).parameters.isEmpty)
        #expect(defaults.bool(forKey: VPhoneFlywheelWebPage.includeIPPreferenceKey) == false)
        #expect(defaults.string(forKey: VPhoneFlywheelWebPage.urlPreferenceKey) == "https://business.example/")
    }

    @Test func unreadablePreferencesAreReportedAndNeverOverwritten() throws {
        let suite = "FlywheelParameterTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let duplicate = VPhoneFlywheelURLParameter(name: "same", value: "1")
        let invalidValues: [Any] = ["wrong type", Data("invalid JSON".utf8), try JSONEncoder().encode([duplicate, duplicate])]
        for invalid in invalidValues {
            defaults.set(invalid, forKey: VPhoneFlywheelURLParameterStore.preferenceKey)
            let before = defaults.object(forKey: VPhoneFlywheelURLParameterStore.preferenceKey) as? NSObject
            let store = VPhoneFlywheelURLParameterStore(defaults: defaults)
            #expect(store.error != nil)
            #expect(store.parameters.isEmpty)
            #expect(defaults.object(forKey: VPhoneFlywheelURLParameterStore.preferenceKey) as? NSObject == before)
        }
    }
}
