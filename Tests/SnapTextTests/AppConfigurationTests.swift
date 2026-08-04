import Testing
@testable import SnapText

@Suite("App configuration")
struct AppConfigurationTests {
    @Test("Visible Screenie name keeps the legacy lookup identity")
    func preservesUpgradeIdentity() {
        #expect(AppConfiguration.appName == "Screenie")
        #expect(AppConfiguration.bundleIdentifier == "com.sohailmohammad.SnapText")
        #expect(AppConfiguration.keychainService == AppConfiguration.bundleIdentifier)
        #expect(AppConfiguration.keychainAccount == "together-api-key")
    }
}
