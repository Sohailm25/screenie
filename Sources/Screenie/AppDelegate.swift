import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private let keychain = KeychainStore(
        service: AppConfiguration.keychainService,
        account: AppConfiguration.keychainAccount
    )
    private let apiClient = TogetherAPIClient()
    private let interactiveCapturer = InteractiveScreenshotCapturer()
    private let hotKeyController = GlobalHotKeyController()
    private let hud = StatusHUD()
    private lazy var folderAccess = ScreenshotFolderAccess(preferences: preferences)
    private var automaticRequestLimiter = AutomaticRequestRateLimiter(
        maximumRequests: AppConfiguration.maximumAutomaticRequestsPerWindow,
        window: AppConfiguration.automaticRequestWindow
    )

    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher?
    private var watchedFolderURL: URL?
    private var captureTask: Task<Void, Never>?
    private var activeCaptureOperationID: UInt64?
    private var captureIsStartingOrActive = false
    private var shortcutCaptureWatcherBoundary: UInt64?
    private var shortcutCaptureOperationID: UInt64?
    private var processingTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?
    private var operationID: UInt64 = 0
    private var monitoringGeneration: UInt64 = 0
    private var pendingText: String?

    private var statusMenuItem: NSMenuItem!
    private var captureMenuItem: NSMenuItem!
    private var processLatestMenuItem: NSMenuItem!
    private var copyReadyMenuItem: NSMenuItem!
    private var monitoringMenuItem: NSMenuItem!
    private var modelMenuItems: [VisionModel: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        if preferences.monitoringEnabled && preferences.hasCurrentCloudUploadConsent {
            startMonitoring(showAlertOnFailure: true)
            if preferences.monitoringEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.promptForAPIKeyIfNeeded()
                }
            }
        } else {
            preferences.monitoringEnabled = false
            showPausedState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        invalidateCurrentOperation()
        hotKeyController.unregister()
        watcher?.stop()
        folderAccess.stopAccessing()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(symbol: "text.viewfinder", description: "Screenie")

        let menu = NSMenu()
        let instructionItem = NSMenuItem(
            title: "Use ⌘⌥4 for capture, text, and clipboard",
            action: nil,
            keyEquivalent: ""
        )
        instructionItem.isEnabled = false
        menu.addItem(instructionItem)

        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        captureMenuItem = NSMenuItem(
            title: "Capture Selection and Copy Text (⌘⌥4)",
            action: #selector(captureSelectionAndCopyText),
            keyEquivalent: ""
        )
        captureMenuItem.target = self
        menu.addItem(captureMenuItem)

        processLatestMenuItem = NSMenuItem(
            title: "Process Latest Screenshot",
            action: #selector(processLatestSelection),
            keyEquivalent: "p"
        )
        processLatestMenuItem.target = self
        menu.addItem(processLatestMenuItem)

        copyReadyMenuItem = NSMenuItem(
            title: "Copy Ready Text",
            action: #selector(copyPendingText),
            keyEquivalent: "c"
        )
        copyReadyMenuItem.target = self
        copyReadyMenuItem.isEnabled = false
        menu.addItem(copyReadyMenuItem)
        menu.addItem(.separator())

        monitoringMenuItem = NSMenuItem(
            title: "Enable Screenie",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        monitoringMenuItem.target = self
        menu.addItem(monitoringMenuItem)

        let chooseFolderItem = NSMenuItem(
            title: "Choose Screenshot Folder…",
            action: #selector(chooseScreenshotFolder),
            keyEquivalent: ""
        )
        chooseFolderItem.target = self
        menu.addItem(chooseFolderItem)

        let systemFolderItem = NSMenuItem(
            title: "Use Current macOS Screenshot Folder",
            action: #selector(useSystemScreenshotFolder),
            keyEquivalent: ""
        )
        systemFolderItem.target = self
        menu.addItem(systemFolderItem)

        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for model in VisionModel.allCases {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.rawValue
            item.state = preferences.model == model ? .on : .off
            modelMenu.addItem(item)
            modelMenuItems[model] = item
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        menu.addItem(.separator())

        let apiKeyItem = NSMenuItem(
            title: "Set Together API Key…",
            action: #selector(setAPIKey),
            keyEquivalent: ""
        )
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        let removeAPIKeyItem = NSMenuItem(
            title: "Remove API Key…",
            action: #selector(removeAPIKey),
            keyEquivalent: ""
        )
        removeAPIKeyItem.target = self
        menu.addItem(removeAPIKeyItem)

        let privacyItem = NSMenuItem(
            title: "Privacy…",
            action: #selector(showPrivacy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        menu.addItem(privacyItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Screenie",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func startMonitoring(showAlertOnFailure: Bool) {
        guard preferences.hasCurrentCloudUploadConsent else {
            preferences.monitoringEnabled = false
            showPausedState()
            return
        }

        invalidateCurrentOperation()
        monitoringGeneration &+= 1
        let generation = monitoringGeneration
        watcher?.stop()
        watcher = nil
        watchedFolderURL = nil
        folderAccess.stopAccessing()

        do {
            let folderURL = try folderAccess.resolve()
            let watcher = ScreenshotWatcher()
            try watcher.start(
                folderURL: folderURL,
                onScreenshot: { [weak self] screenshot in
                    DispatchQueue.main.async {
                        self?.handleDetectedSelection(screenshot, generation: generation)
                    }
                },
                onFailure: { [weak self] error in
                    DispatchQueue.main.async {
                        self?.monitoringFailed(error, generation: generation)
                    }
                }
            )

            self.watcher = watcher
            watchedFolderURL = folderURL
            preferences.monitoringEnabled = true
            captureMenuItem.isEnabled = true
            registerCaptureShortcut(showAlertOnFailure: showAlertOnFailure)
            monitoringMenuItem.title = "Pause Screenie"
            statusMenuItem.title = "Watching \(displayPath(folderURL))"
            updateStatusIcon(symbol: "text.viewfinder", description: "Watching for selection screenshots")
        } catch {
            preferences.monitoringEnabled = false
            showPausedState()
            let message = shortMessage(for: error)
            statusMenuItem.title = message
            hud.showError(message)
            if showAlertOnFailure {
                showAlert(title: "Could not watch the screenshot folder", message: error.localizedDescription)
            }
        }
    }

    private func stopMonitoring() {
        invalidateCurrentOperation()
        monitoringGeneration &+= 1
        watcher?.stop()
        watcher = nil
        watchedFolderURL = nil
        folderAccess.stopAccessing()
        preferences.monitoringEnabled = false
        showPausedState()
    }

    private func showPausedState() {
        hotKeyController.unregister()
        captureMenuItem?.isEnabled = false
        monitoringMenuItem?.title = "Enable Screenie"
        statusMenuItem?.title = "Screenie paused"
        updateStatusIcon(symbol: "pause.circle", description: "Screenie paused")
    }

    private func monitoringFailed(_ error: Error, generation: UInt64) {
        guard generation == monitoringGeneration else { return }
        invalidateCurrentOperation()
        watcher = nil
        watchedFolderURL = nil
        folderAccess.stopAccessing()
        preferences.monitoringEnabled = false
        showPausedState()
        let message = shortMessage(for: error)
        statusMenuItem.title = message
        hud.showError(message)
    }

    private func registerCaptureShortcut(showAlertOnFailure: Bool) {
        do {
            try hotKeyController.register { [weak self] in
                self?.captureSelectionAndCopyText()
            }
        } catch {
            let message = shortMessage(for: error)
            hud.showError(message)
            if showAlertOnFailure {
                showAlert(
                    title: "Command-Option-4 is unavailable",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func handleDetectedSelection(_ screenshot: DetectedScreenshot, generation: UInt64) {
        guard
            preferences.monitoringEnabled,
            generation == monitoringGeneration,
            ScreenshotOperationOrdering.watchedCaptureShouldSupersedeShortcut(
                discoverySequence: screenshot.discoverySequence,
                shortcutBoundary: shortcutCaptureWatcherBoundary
            )
        else { return }
        let currentOperationID = beginOperation()
        processSelection(
            at: screenshot.url,
            expectedIdentity: screenshot.identity,
            source: .watchedSelection,
            operationID: currentOperationID
        )
    }

    @objc private func captureSelectionAndCopyText() {
        guard preferences.monitoringEnabled, !captureIsStartingOrActive else { return }
        captureIsStartingOrActive = true
        let watcherBoundary = watcher?.captureOrderingBoundary()

        let currentOperationID = beginOperation()
        shortcutCaptureWatcherBoundary = watcherBoundary
        shortcutCaptureOperationID = currentOperationID
        var handedOffToCaptureTask = false
        defer {
            if !handedOffToCaptureTask {
                captureIsStartingOrActive = false
                completeShortcutCaptureOperation(
                    ifMatching: currentOperationID,
                    retainOrderingBoundary: false
                )
            }
        }
        guard ensureCloudUploadConsent() else { return }
        guard capturePreflightIsCurrent(currentOperationID) else { return }
        guard apiKeyIsAvailableForCapture() else { return }
        guard capturePreflightIsCurrent(currentOperationID) else { return }
        guard ensureScreenCaptureAccess() else { return }
        guard capturePreflightIsCurrent(currentOperationID) else { return }

        let folderURL: URL
        do {
            folderURL = try activeScreenshotFolder()
        } catch {
            failProcessing(
                error,
                for: currentOperationID,
                retainShortcutOrderingBoundary: false
            )
            return
        }

        let workspace: ScreenshotCaptureWorkspace
        do {
            workspace = try ScreenshotCaptureWorkspace.create(in: folderURL)
        } catch {
            failProcessing(
                error,
                for: currentOperationID,
                retainShortcutOrderingBoundary: false
            )
            return
        }

        statusMenuItem.title = "Select a region…"
        updateStatusIcon(symbol: "viewfinder", description: "Select a screenshot region")
        activeCaptureOperationID = currentOperationID
        let startingClipboardChangeCount = NSPasteboard.general.changeCount
        handedOffToCaptureTask = true
        captureTask = Task { [weak self] in
            guard let self else {
                workspace.remove()
                return
            }
            var preserveUnpublishedCapture = false
            var didStartShortcutProcessing = false
            var didPublishShortcutCapture = false
            defer {
                if
                    !preserveUnpublishedCapture
                        || !InteractiveScreenshotCapturer
                            .pathExistsWithoutFollowingSymbolicLinks(workspace.captureURL)
                {
                    workspace.remove()
                }
                if self.activeCaptureOperationID == currentOperationID {
                    self.activeCaptureOperationID = nil
                    self.captureTask = nil
                    self.captureIsStartingOrActive = false
                    if !didStartShortcutProcessing {
                        self.completeShortcutCaptureOperation(
                            ifMatching: currentOperationID,
                            retainOrderingBoundary: didPublishShortcutCapture
                        )
                    }
                }
            }
            do {
                let result = try await self.interactiveCapturer.capture(
                    to: workspace.captureURL
                )

                switch result {
                case .cancelled:
                    try Task.checkCancellation()
                    guard currentOperationID == self.operationID else { return }
                    if !CGPreflightScreenCaptureAccess() {
                        self.showScreenCaptureAccessRequired()
                    } else if NSPasteboard.general.changeCount != startingClipboardChangeCount {
                        self.showCaptureChangedClipboardState()
                    } else {
                        self.showCaptureCancelledState()
                    }
                case let .captured(identity):
                    preserveUnpublishedCapture = true
                    let destinationURL: URL
                    do {
                        destinationURL = try self.publishCapturedScreenshot(
                            from: workspace.captureURL,
                            expectedIdentity: identity,
                            in: folderURL
                        )
                    } catch {
                        if InteractiveScreenshotCapturer
                            .pathExistsWithoutFollowingSymbolicLinks(workspace.captureURL)
                        {
                            throw CapturePublishError.captureRemainsInWorkspace(
                                workspace.captureURL
                            )
                        }
                        throw error
                    }
                    preserveUnpublishedCapture = false
                    didPublishShortcutCapture = true
                    try Task.checkCancellation()
                    guard currentOperationID == self.operationID else { return }

                    didStartShortcutProcessing = true
                    self.processSelection(
                        at: destinationURL,
                        expectedIdentity: identity,
                        source: .shortcut,
                        operationID: currentOperationID
                    )
                }
            } catch is CancellationError {
                if let identity = InteractiveScreenshotCapturer.completedCaptureIdentity(
                    at: workspace.captureURL
                ) {
                    preserveUnpublishedCapture = true
                    if (try? self.publishCapturedScreenshot(
                        from: workspace.captureURL,
                        expectedIdentity: identity,
                        in: folderURL
                    )) != nil {
                        preserveUnpublishedCapture = false
                        didPublishShortcutCapture = true
                    }
                }
                return
            } catch {
                if InteractiveScreenshotCapturer.completedCaptureIdentity(
                    at: workspace.captureURL
                ) != nil {
                    preserveUnpublishedCapture = true
                }
                guard currentOperationID == self.operationID else { return }
                self.failProcessing(
                    error,
                    for: currentOperationID,
                    retainShortcutOrderingBoundary: didPublishShortcutCapture
                )
            }
        }
    }

    private func capturePreflightIsCurrent(_ expectedOperationID: UInt64) -> Bool {
        preferences.monitoringEnabled && expectedOperationID == operationID
    }

    private func publishCapturedScreenshot(
        from stagedURL: URL,
        expectedIdentity: ScreenshotFileIdentity,
        in folderURL: URL
    ) throws -> URL {
        let destinationURL = try ScreenshotCaptureDestination.makeUniquePNGURL(in: folderURL)
        let activeWatcher: ScreenshotWatcher?
        if watchedFolderURL?.standardizedFileURL == folderURL.standardizedFileURL {
            activeWatcher = watcher
        } else {
            activeWatcher = nil
        }

        activeWatcher?.ignoreNextAppearance(of: expectedIdentity, at: destinationURL)
        do {
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
        } catch {
            activeWatcher?.cancelIgnoredAppearance(
                of: expectedIdentity,
                at: destinationURL
            )
            throw error
        }

        guard let publishedIdentity = ScreenshotFileIdentity.regularFile(
            at: destinationURL
        ) else {
            activeWatcher?.cancelIgnoredAppearance(
                of: expectedIdentity,
                at: destinationURL
            )
            throw ScreenshotImageLoadError.changedBeforeRead
        }
        activeWatcher?.finishIgnoredAppearance(
            expectedIdentity: expectedIdentity,
            observedIdentity: publishedIdentity,
            at: destinationURL
        )
        guard publishedIdentity == expectedIdentity else {
            throw ScreenshotImageLoadError.changedBeforeRead
        }
        return destinationURL
    }

    private func apiKeyIsAvailableForCapture() -> Bool {
        do {
            guard let key = try loadAPIKey(), !key.isEmpty else {
                statusMenuItem.title = "Together API key required"
                hud.showError("Save a Together API key before capturing a region.")
                promptForAPIKey()
                return false
            }
            return true
        } catch {
            failProcessing(error)
            return false
        }
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }

        showScreenCaptureAccessRequired()
        return false
    }

    private func showScreenCaptureAccessRequired() {
        let alert = NSAlert()
        alert.messageText = "Allow Screen Recording for Screenie"
        alert.informativeText = "macOS requires Screen Recording access before Screenie can open Apple’s region selector. Grant access in Privacy & Security, then reopen Screenie if macOS asks you to."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
            let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        {
            NSWorkspace.shared.open(settingsURL)
        }
        statusMenuItem.title = "Screen Recording access required"
        hud.showError("Screen Recording access is required for the ⌘⌥4 selector.")
    }

    private func showCaptureChangedClipboardState() {
        statusMenuItem.title = "Clipboard changed during capture; no cloud request"
        updateStatusIcon(symbol: "doc.on.clipboard", description: "Capture changed clipboard")
        hud.showSuccess("The clipboard changed while Apple’s selector was open. Screenie sent no image to Together.")
    }

    private func showCaptureCancelledState() {
        guard preferences.monitoringEnabled else {
            showPausedState()
            return
        }
        if let watchedFolderURL {
            statusMenuItem.title = "Capture canceled; watching \(displayPath(watchedFolderURL))"
        } else {
            statusMenuItem.title = "Capture canceled"
        }
        updateStatusIcon(symbol: "text.viewfinder", description: "Waiting for a screenshot")
    }

    private func activeScreenshotFolder() throws -> URL {
        if let watchedFolderURL {
            return watchedFolderURL
        }
        return try folderAccess.resolve()
    }

    @objc private func toggleMonitoring() {
        if preferences.monitoringEnabled {
            stopMonitoring()
        } else {
            enableMonitoring()
        }
    }

    @objc private func chooseScreenshotFolder() {
        guard !captureIsStartingOrActive else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the macOS screenshot folder"
        panel.prompt = "Watch Folder"
        panel.message = "Screenie saves ⌘⌥4 captures here. While enabled, it also watches this folder for new Apple selection screenshots."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = watchedFolderURL ?? ScreenshotFolderResolver.systemScreenshotFolder()

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let wasMonitoring = preferences.monitoringEnabled
            invalidateCurrentOperation()
            try folderAccess.save(url)
            if wasMonitoring {
                startMonitoring(showAlertOnFailure: true)
            } else {
                watchedFolderURL = nil
                folderAccess.stopAccessing()
                showPausedState()
                statusMenuItem.title = "Folder saved; Screenie paused"
                hud.showSuccess("Folder saved. Enable Screenie when ready.")
            }
        } catch {
            showAlert(title: "Could not use that folder", message: error.localizedDescription)
        }
    }

    @objc private func useSystemScreenshotFolder() {
        guard !captureIsStartingOrActive else { return }
        let wasMonitoring = preferences.monitoringEnabled
        invalidateCurrentOperation()
        folderAccess.useCurrentSystemFolder()
        if wasMonitoring {
            startMonitoring(showAlertOnFailure: true)
        } else {
            watchedFolderURL = nil
            folderAccess.stopAccessing()
            showPausedState()
            statusMenuItem.title = "System folder selected; Screenie paused"
            hud.showSuccess("System screenshot folder selected. Enable Screenie when ready.")
        }
    }

    @objc private func processLatestSelection() {
        let currentOperationID = beginOperation()
        guard ensureCloudUploadConsent() else { return }

        let folderURL: URL
        do {
            if let watchedFolderURL {
                folderURL = watchedFolderURL
            } else {
                folderURL = try folderAccess.resolve()
            }
        } catch {
            hud.showError(shortMessage(for: error))
            return
        }

        statusMenuItem.title = "Finding latest screenshot…"
        lookupTask = Task { [weak self] in
            let screenshot = await Task.detached(priority: .userInitiated) {
                ScreenshotWatcher.latestScreenshot(in: folderURL)
            }.value
            guard
                let self,
                !Task.isCancelled,
                currentOperationID == self.operationID
            else { return }
            self.lookupTask = nil
            guard let screenshot else {
                self.statusMenuItem.title = "No supported screenshot found"
                self.hud.showError("No supported screenshot found in \(self.displayPath(folderURL)).")
                return
            }
            self.processSelection(
                at: screenshot.url,
                expectedIdentity: screenshot.identity,
                source: .manual,
                operationID: currentOperationID
            )
        }
    }

    private func processSelection(
        at url: URL,
        expectedIdentity: ScreenshotFileIdentity?,
        source: ScreenshotProcessingSource,
        operationID currentOperationID: UInt64
    ) {
        guard
            currentOperationID == operationID,
            preferences.hasCurrentCloudUploadConsent
        else { return }

        let apiKey: String
        do {
            guard let savedKey = try loadAPIKey(), !savedKey.isEmpty else {
                statusMenuItem.title = "Together API key required"
                hud.showError("Save a Together API key, then choose Process Latest Screenshot.")
                completeShortcutCaptureOperation(
                    ifMatching: currentOperationID,
                    retainOrderingBoundary: true
                )
                return
            }
            apiKey = savedKey
        } catch {
            failProcessing(error, for: currentOperationID)
            return
        }

        guard currentOperationID == operationID else {
            return
        }

        if source.consumesRequestQuota && !automaticRequestLimiter.accept() {
            statusMenuItem.title = "Capture request limit reached"
            hud.showError(
                "Screenie reached its safety cap of \(AppConfiguration.maximumAutomaticRequestsPerWindow) capture requests in \(AppConfiguration.automaticRequestWindowSeconds) seconds. The screenshot was saved. Use Process Latest Screenshot for an explicit retry."
            )
            completeShortcutCaptureOperation(
                ifMatching: currentOperationID,
                retainOrderingBoundary: true
            )
            return
        }

        let startingClipboardChangeCount = NSPasteboard.general.changeCount
        let model = preferences.model
        let start = ContinuousClock.now

        statusMenuItem.title = "Reading \(url.lastPathComponent)…"
        updateStatusIcon(symbol: "ellipsis.circle", description: "Reading screenshot text")
        hud.showProgress("Reading text with \(model.displayName)…")

        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadTask = Task.detached(priority: .userInitiated) {
                    try ScreenshotImageLoader.load(
                        from: url,
                        expectedIdentity: expectedIdentity,
                        requiresSelectionMetadata: source.requiresSelectionMetadata
                    )
                }
                let image = try await withTaskCancellationHandler {
                    try await loadTask.value
                } onCancel: {
                    loadTask.cancel()
                }
                try Task.checkCancellation()

                let text = try await self.apiClient.transcribe(
                    imageData: image.data,
                    mimeType: image.mimeType,
                    apiKey: apiKey,
                    model: model
                )
                try Task.checkCancellation()
                guard currentOperationID == self.operationID else { return }

                self.finish(
                    text: text,
                    startingClipboardChangeCount: startingClipboardChangeCount,
                    elapsed: start.duration(to: .now),
                    operationID: currentOperationID
                )
            } catch {
                guard !Task.isCancelled, currentOperationID == self.operationID else { return }
                self.failProcessing(error, for: currentOperationID)
            }
        }
    }

    private func finish(
        text: String,
        startingClipboardChangeCount: Int,
        elapsed: Duration,
        operationID: UInt64
    ) {
        let pasteboard = NSPasteboard.general
        if ClipboardCommitPolicy.shouldWrite(
            startingChangeCount: startingClipboardChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) {
            guard ClipboardWriter.write(text, pasteboard: pasteboard) else {
                failProcessing(ClipboardError.writeFailed, for: operationID)
                return
            }
            pendingText = nil
            copyReadyMenuItem.isEnabled = false
            copyReadyMenuItem.title = "Copy Ready Text"
            statusMenuItem.title = "Copied \(text.count) characters in \(format(elapsed))"
            updateStatusIcon(symbol: "checkmark.circle", description: "Screenshot text copied")
            hud.showSuccess("Copied \(text.count) characters in \(format(elapsed)).")
        } else {
            pendingText = text
            copyReadyMenuItem.isEnabled = true
            copyReadyMenuItem.title = "Copy Ready Text (\(text.count) characters)"
            statusMenuItem.title = "Text ready; clipboard left unchanged"
            updateStatusIcon(symbol: "doc.on.clipboard", description: "Screenshot text ready to copy")
            hud.showSuccess("Text is ready. Your newer clipboard content was left unchanged.")
        }
        if operationID == self.operationID {
            processingTask = nil
            completeShortcutCaptureOperation(
                ifMatching: operationID,
                retainOrderingBoundary: true
            )
        }
    }

    private func failProcessing(
        _ error: Error,
        for operationID: UInt64? = nil,
        retainShortcutOrderingBoundary: Bool = true
    ) {
        let message = shortMessage(for: error)
        statusMenuItem.title = message
        updateStatusIcon(symbol: "exclamationmark.triangle", description: "Screenie error")
        hud.showError(message)
        if let operationID, operationID == self.operationID {
            processingTask = nil
            completeShortcutCaptureOperation(
                ifMatching: operationID,
                retainOrderingBoundary: retainShortcutOrderingBoundary
            )
        }
        NSSound.beep()
    }

    @objc private func copyPendingText() {
        guard let pendingText else { return }
        guard ClipboardWriter.write(pendingText) else {
            failProcessing(ClipboardError.writeFailed)
            return
        }
        self.pendingText = nil
        copyReadyMenuItem.isEnabled = false
        copyReadyMenuItem.title = "Copy Ready Text"
        statusMenuItem.title = "Ready text copied"
        updateStatusIcon(symbol: "checkmark.circle", description: "Screenshot text copied")
        hud.showSuccess("Ready text copied.")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let model = VisionModel(rawValue: rawValue)
        else { return }

        preferences.model = model
        for (candidate, item) in modelMenuItems {
            item.state = candidate == model ? .on : .off
        }
        statusMenuItem.title = "Using \(model.displayName)"
    }

    @objc private func setAPIKey() {
        promptForAPIKey()
    }

    @objc private func removeAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Remove the Together API key?"
        alert.informativeText = "Screenie will stop sending screenshots until you save another key."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try keychain.delete()
            invalidateCurrentOperation()
            statusMenuItem.title = "API key removed"
        } catch {
            showAlert(title: "Could not remove the key", message: error.localizedDescription)
        }
    }

    private func promptForAPIKeyIfNeeded() {
        do {
            guard try loadAPIKey() == nil else { return }
        } catch {
            showAlert(title: "Could not read the saved key", message: error.localizedDescription)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.promptForAPIKey()
        }
    }

    private func promptForAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Together API key"
        alert.informativeText = "Screenie stores the key in macOS Keychain. It is sent only to api.together.xyz."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Paste your Together API key"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            showAlert(title: "No key saved", message: "Paste a non-empty Together API key.")
            return
        }

        do {
            try keychain.save(value)
            statusMenuItem.title = "API key saved"
            hud.showSuccess("Together API key saved in Keychain.")
        } catch {
            showAlert(title: "Could not save the key", message: error.localizedDescription)
        }
    }

    private func loadAPIKey() throws -> String? {
        try keychain.read()
    }

    private func showOnboarding() {
        guard !preferences.monitoringEnabled else { return }
        let folder = configuredFolderForDisclosure()
        let alert = NSAlert()
        alert.messageText = "Enable screenshot-to-clipboard?"
        alert.informativeText = cloudUploadDisclosure(for: folder)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Choose Folder")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            preferences.recordCloudUploadConsent()
            preferences.monitoringEnabled = true
            startMonitoring(showAlertOnFailure: true)
            promptForAPIKeyIfNeeded()
        case .alertSecondButtonReturn:
            chooseScreenshotFolder()
        default:
            showPausedState()
        }
    }

    @objc private func showPrivacy() {
        showAlert(
            title: "Screenie privacy",
            message: "Command-Option-4 opens Apple’s region selector. After you finish the selection, Screenie saves the PNG in your configured screenshot folder and sends it to api.together.xyz in an HTTPS request. While enabled, Screenie also sends new files carrying Apple selection-screenshot metadata. Process Latest Screenshot explicitly sends the newest supported image. Images larger than 16 MiB, 64 megapixels, or 16,384 pixels on one side are rejected. Screenie keeps no request history, and the API key is stored in macOS Keychain."
        )
    }

    private func enableMonitoring() {
        guard ensureCloudUploadConsent() else {
            preferences.monitoringEnabled = false
            showPausedState()
            return
        }
        preferences.monitoringEnabled = true
        startMonitoring(showAlertOnFailure: true)
        promptForAPIKeyIfNeeded()
    }

    private func ensureCloudUploadConsent() -> Bool {
        guard !preferences.hasCurrentCloudUploadConsent else { return true }

        let folder = configuredFolderForDisclosure()
        let alert = NSAlert()
        alert.messageText = "Allow cloud transcription?"
        alert.informativeText = cloudUploadDisclosure(for: folder)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        preferences.recordCloudUploadConsent()
        return true
    }

    private func cloudUploadDisclosure(for folder: URL) -> String {
        "While Screenie is enabled, Command-Option-4 opens Apple’s region selector. Finishing a selection saves a PNG in \(displayPath(folder)) and sends it to Together without another confirmation. Screenie also watches that folder and sends new files carrying Apple selection-screenshot metadata, including captures made with Command-Shift-4. Process Latest Screenshot sends the newest supported image even without that metadata. Existing files are ignored by monitoring. Each processed image can incur charges on your Together account."
    }

    private func configuredFolderForDisclosure() -> URL {
        if let watchedFolderURL {
            return watchedFolderURL
        }
        if let path = preferences.screenshotFolderPath {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return ScreenshotFolderResolver.systemScreenshotFolder()
    }

    @discardableResult
    private func beginOperation() -> UInt64 {
        clearShortcutCaptureBoundary()
        operationID &+= 1
        cancelOperationTasks()
        return operationID
    }

    private func invalidateCurrentOperation() {
        clearShortcutCaptureBoundary()
        operationID &+= 1
        cancelOperationTasks()
    }

    private func cancelOperationTasks() {
        captureTask?.cancel()
        processingTask?.cancel()
        lookupTask?.cancel()
        processingTask = nil
        lookupTask = nil
    }

    private func completeShortcutCaptureOperation(
        ifMatching expectedOperationID: UInt64,
        retainOrderingBoundary: Bool
    ) {
        guard shortcutCaptureOperationID == expectedOperationID else { return }
        shortcutCaptureOperationID = nil
        if !retainOrderingBoundary {
            shortcutCaptureWatcherBoundary = nil
        }
    }

    private func clearShortcutCaptureBoundary() {
        shortcutCaptureWatcherBoundary = nil
        shortcutCaptureOperationID = nil
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func updateStatusIcon(symbol: String, description: String) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    private func shortMessage(for error: Error) -> String {
        let message = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.count <= 88 {
            return message
        }
        return String(message.prefix(85)) + "…"
    }

    private func format(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.2fs", seconds)
    }
}

private enum ClipboardError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "macOS rejected the clipboard update."
    }
}

private enum CapturePublishError: LocalizedError {
    case captureRemainsInWorkspace(URL)

    var errorDescription: String? {
        switch self {
        case let .captureRemainsInWorkspace(url):
            return "The screenshot could not be moved to a visible name. It remains at \(url.path)."
        }
    }
}
