import Foundation

enum ScreenshotFolderError: LocalizedError {
    case unavailable(URL)
    case bookmarkUnreadable

    var errorDescription: String? {
        switch self {
        case let .unavailable(url):
            return "The screenshot folder is unavailable: \(url.path)"
        case .bookmarkUnreadable:
            return "The saved screenshot-folder permission is no longer valid. Choose the folder again."
        }
    }
}

enum ScreenshotFolderResolver {
    static func systemScreenshotFolder(
        defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture"),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let rawLocation = defaults?.string(forKey: "location"), !rawLocation.isEmpty else {
            return homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        }

        if rawLocation.hasPrefix("file://"), let fileURL = URL(string: rawLocation) {
            return fileURL.standardizedFileURL
        }

        let expanded = (rawLocation as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
}

@MainActor
final class ScreenshotFolderAccess {
    private let preferences: AppPreferences
    private var activeSecurityScopedURL: URL?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func resolve() throws -> URL {
        stopAccessing()

        if let bookmark = preferences.screenshotFolderBookmark {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                try validateDirectory(url)

                if url.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURL = url
                }
                if isStale {
                    saveBookmark(for: url)
                }
                preferences.screenshotFolderPath = url.path
                return url
            } catch {
                if preferences.screenshotFolderPath == nil {
                    throw ScreenshotFolderError.bookmarkUnreadable
                }
            }
        }

        let url: URL
        if let path = preferences.screenshotFolderPath {
            url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else {
            url = ScreenshotFolderResolver.systemScreenshotFolder()
        }
        try validateDirectory(url)
        return url
    }

    func save(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        try validateDirectory(normalized)
        preferences.screenshotFolderPath = normalized.path
        saveBookmark(for: normalized)
    }

    func useCurrentSystemFolder() {
        preferences.clearScreenshotFolderOverride()
    }

    func stopAccessing() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    private func saveBookmark(for url: URL) {
        preferences.screenshotFolderBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ScreenshotFolderError.unavailable(url)
        }
    }
}
