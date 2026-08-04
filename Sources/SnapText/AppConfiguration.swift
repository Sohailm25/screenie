import Foundation

enum AppConfiguration {
    static let appName = "Screenie"
    // Retained so Screenie uses the existing preference domain and locates the legacy Keychain item.
    static let bundleIdentifier = "com.sohailmohammad.SnapText"
    static let apiEndpoint = URL(string: "https://api.together.xyz/v1/chat/completions")!
    static let keychainService = bundleIdentifier
    static let keychainAccount = "together-api-key"
    static let maximumOutputTokens = 3_072
    static let maximumASCIIChartCharactersPerLine = 72
    static let maximumASCIIChartLines = 20
    static let maximumTotalASCIILines = 60
    static let cloudUploadConsentVersion = 2
    static let maximumInputBytes = 16 * 1_024 * 1_024
    static let maximumPixelCount = 64_000_000
    static let maximumImageDimension = 16_384
    static let maximumAutomaticRequestsPerWindow = 12
    static let automaticRequestWindowSeconds = 60
    static let automaticRequestWindow: Duration = .seconds(automaticRequestWindowSeconds)
}

enum VisionModel: String, CaseIterable, Sendable {
    case fast = "Qwen/Qwen3.5-9B"
    case accurate = "google/gemma-4-31B-it"

    var displayName: String {
        switch self {
        case .fast:
            return "Fast: Qwen3.5 9B"
        case .accurate:
            return "Accurate: Gemma 4 31B"
        }
    }
}

@MainActor
final class AppPreferences {
    private enum Key {
        static let model = "visionModel"
        static let monitoringEnabled = "monitoringEnabled"
        static let cloudUploadConsentVersion = "cloudUploadConsentVersion"
        static let screenshotFolderPath = "screenshotFolderPath"
        static let screenshotFolderBookmark = "screenshotFolderBookmark"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var model: VisionModel {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.model),
                let model = VisionModel(rawValue: rawValue)
            else {
                return .fast
            }
            return model
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.model)
        }
    }

    var monitoringEnabled: Bool {
        get { defaults.bool(forKey: Key.monitoringEnabled) }
        set { defaults.set(newValue, forKey: Key.monitoringEnabled) }
    }

    var hasCurrentCloudUploadConsent: Bool {
        defaults.integer(forKey: Key.cloudUploadConsentVersion)
            == AppConfiguration.cloudUploadConsentVersion
    }

    func recordCloudUploadConsent() {
        defaults.set(
            AppConfiguration.cloudUploadConsentVersion,
            forKey: Key.cloudUploadConsentVersion
        )
    }

    var screenshotFolderPath: String? {
        get { defaults.string(forKey: Key.screenshotFolderPath) }
        set { defaults.set(newValue, forKey: Key.screenshotFolderPath) }
    }

    var screenshotFolderBookmark: Data? {
        get { defaults.data(forKey: Key.screenshotFolderBookmark) }
        set { defaults.set(newValue, forKey: Key.screenshotFolderBookmark) }
    }

    func clearScreenshotFolderOverride() {
        defaults.removeObject(forKey: Key.screenshotFolderPath)
        defaults.removeObject(forKey: Key.screenshotFolderBookmark)
    }
}
