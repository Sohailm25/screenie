import Testing
@testable import Screenie

@Suite("App configuration")
struct AppConfigurationTests {
    @Test("Screenie owns its bundle and Keychain identity")
    func usesScreenieIdentity() {
        #expect(AppConfiguration.appName == "Screenie")
        #expect(AppConfiguration.bundleIdentifier == "com.sohailmohammad.Screenie")
        #expect(AppConfiguration.bundleIdentifier != "com.sohailmohammad.SnapText")
        #expect(AppConfiguration.keychainService == AppConfiguration.bundleIdentifier)
        #expect(AppConfiguration.keychainAccount == "together-api-key")
    }
}
