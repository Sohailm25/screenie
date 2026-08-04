enum ScreenshotProcessingSource: Equatable, Sendable {
    case watchedSelection
    case shortcut
    case manual

    var requiresSelectionMetadata: Bool {
        self == .watchedSelection
    }

    var consumesRequestQuota: Bool {
        switch self {
        case .watchedSelection, .shortcut:
            return true
        case .manual:
            return false
        }
    }
}
