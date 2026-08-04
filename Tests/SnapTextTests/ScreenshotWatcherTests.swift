import Darwin
import Foundation
import Testing
@testable import SnapText

@Suite("Screenshot folder watcher", .serialized)
struct ScreenshotWatcherTests {
    private enum WatchEvent: Equatable, Sendable {
        case screenshot(URL)
        case failure(String)
    }

    @Test("Files present when monitoring starts are ignored")
    func ignoresFilesPresentAtStart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingURL = directory.appendingPathComponent("existing.png")
        try pngData().write(to: existingURL)
        try markAsAppleCapture(existingURL, type: "selection")

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let event = await firstEvent(from: stream, timeoutNanoseconds: 700_000_000)

        #expect(event == nil)
    }

    @Test("Monitoring fails when the existing-file baseline cannot be read")
    func rejectsUnreadableBaseline() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingURL = directory.appendingPathComponent("existing.png")
        try pngData().write(to: existingURL)
        try markAsAppleCapture(existingURL, type: "selection")

        let fileManager = FailingFirstEnumerationFileManager()
        let watcher = ScreenshotWatcher(fileManager: fileManager)

        do {
            try watcher.start(
                folderURL: directory,
                onScreenshot: { _ in },
                onFailure: { _ in }
            )
            Issue.record("Expected an unreadable baseline to stop monitoring startup.")
        } catch {
            #expect(fileManager.enumerationCount == 1)
        }
    }

    @Test("Monitoring fails if the watched path changes during startup")
    func rejectsFolderReplacementDuringStartup() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watchedFolder = root.appendingPathComponent("watched", isDirectory: true)
        let movedFolder = root.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(
            at: watchedFolder,
            withIntermediateDirectories: true
        )

        let fileManager = ReplacingBaselineFolderFileManager(movedFolder: movedFolder)
        let watcher = ScreenshotWatcher(fileManager: fileManager)

        do {
            try watcher.start(
                folderURL: watchedFolder,
                onScreenshot: { _ in },
                onFailure: { _ in }
            )
            Issue.record("Expected a replaced folder path to stop monitoring startup.")
        } catch {
            #expect(fileManager.didReplaceFolder)
        }
    }

    @Test("Registration performs a scan after the source becomes active")
    func scansAfterSourceRegistration() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileManager = CountingEnumerationFileManager()
        let watcher = ScreenshotWatcher(fileManager: fileManager)
        defer { watcher.stop() }

        try watcher.start(
            folderURL: directory,
            onScreenshot: { _ in },
            onFailure: { _ in }
        )

        for _ in 0..<20 where fileManager.enumerationCount < 3 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(fileManager.enumerationCount >= 3)
    }

    @Test("The shortcut boundary includes a discovered callback that has not emitted yet")
    func capturesDelayedCallbackInOrderingBoundary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startScreenshotStream(
            watcher: watcher,
            folder: directory
        )
        defer {
            watcher.stop()
            continuation.finish()
        }

        let screenshotURL = directory.appendingPathComponent("pending-before-shortcut.png")
        try pngData().write(to: screenshotURL)
        try markAsAppleCapture(screenshotURL, type: "selection")

        let boundary = watcher.captureOrderingBoundary()
        let screenshot = await firstScreenshot(
            from: stream,
            timeoutNanoseconds: 3_000_000_000
        )

        #expect(screenshot != nil)
        #expect(screenshot?.discoverySequence ?? .max <= boundary)
    }

    @Test("A screenshot discovered after the shortcut boundary wins with an old timestamp")
    func ordersCopiedScreenshotByDiscoverySequence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startScreenshotStream(
            watcher: watcher,
            folder: directory
        )
        defer {
            watcher.stop()
            continuation.finish()
        }

        let boundary = watcher.captureOrderingBoundary()
        let oldTimestamp = Date(timeIntervalSince1970: 1_000)
        let screenshotURL = directory.appendingPathComponent("copied-after-shortcut.png")
        try pngData().write(to: screenshotURL)
        try markAsAppleCapture(screenshotURL, type: "selection")
        try FileManager.default.setAttributes(
            [.modificationDate: oldTimestamp],
            ofItemAtPath: screenshotURL.path
        )

        let screenshot = await firstScreenshot(
            from: stream,
            timeoutNanoseconds: 3_000_000_000
        )

        #expect(screenshot?.discoverySequence ?? 0 > boundary)
        #expect(screenshot?.modificationDate == oldTimestamp)
    }

    @Test("New PNG is detected when selection metadata arrives after creation")
    func detectsSelectionWhenMetadataArrivesAfterCreation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let screenshotURL = directory.appendingPathComponent("new-selection.png")
        try pngData().write(to: screenshotURL)
        try await Task.sleep(nanoseconds: 90_000_000)
        try markAsAppleCapture(screenshotURL, type: "selection")

        let event = await firstEvent(from: stream, timeoutNanoseconds: 3_000_000_000)
        assertScreenshotEvent(event, matches: screenshotURL)
    }

    @Test("New Apple window capture is ignored")
    func ignoresNewWindowCapture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let screenshotURL = directory.appendingPathComponent("new-window.png")
        try pngData().write(to: screenshotURL)
        try markAsAppleCapture(screenshotURL, type: "window")

        let event = await firstEvent(from: stream, timeoutNanoseconds: 900_000_000)

        #expect(event == nil)
    }

    @Test("An oversized selection reaches the loader without watcher image parsing")
    func detectsOversizedSelectionForSafeRejection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let screenshotURL = directory.appendingPathComponent("oversized-selection.png")
        FileManager.default.createFile(atPath: screenshotURL.path, contents: Data([0]))
        let handle = try FileHandle(forWritingTo: screenshotURL)
        try handle.truncate(atOffset: UInt64(AppConfiguration.maximumInputBytes + 1))
        try handle.close()
        try markAsAppleCapture(screenshotURL, type: "selection")

        let event = await firstEvent(from: stream, timeoutNanoseconds: 3_000_000_000)
        assertScreenshotEvent(event, matches: screenshotURL)
    }

    @Test("A zero-byte entry remains pending until image bytes and metadata arrive")
    func detectsScreenshotCompletedAfterDelayedRescan() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let screenshotURL = directory.appendingPathComponent("slow-selection.png")
        FileManager.default.createFile(atPath: screenshotURL.path, contents: Data())
        try await Task.sleep(nanoseconds: 260_000_000)
        try pngData().write(to: screenshotURL)
        try markAsAppleCapture(screenshotURL, type: "selection")

        let event = await firstEvent(from: stream, timeoutNanoseconds: 3_000_000_000)
        assertScreenshotEvent(event, matches: screenshotURL)
    }

    @Test("A newer zero-byte candidate is not suppressed by an older complete image")
    func preservesOrderingForIncompleteCandidate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let olderURL = directory.appendingPathComponent("older-selection.png")
        try pngData().write(to: olderURL)
        try markAsAppleCapture(olderURL, type: "selection")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: olderURL.path
        )

        let newerURL = directory.appendingPathComponent("newer-selection.png")
        FileManager.default.createFile(atPath: newerURL.path, contents: Data())
        try markAsAppleCapture(newerURL, type: "selection")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newerURL.path
        )

        let watcher = ScreenshotWatcher(fileManager: SkippingFirstEnumerationFileManager())
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        try await Task.sleep(nanoseconds: 160_000_000)
        try pngData().write(to: newerURL)

        let detectedNewer = await containsScreenshot(
            newerURL,
            in: stream,
            timeoutNanoseconds: 3_000_000_000
        )
        #expect(detectedNewer)
    }

    @Test("A pending file keeps its identity after a rename")
    func detectsPendingScreenshotAfterRename() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let originalURL = directory.appendingPathComponent("unresolved.png")
        let renamedURL = directory.appendingPathComponent("renamed-selection.png")
        try pngData().write(to: originalURL)
        try await Task.sleep(nanoseconds: 90_000_000)
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        try await Task.sleep(nanoseconds: 90_000_000)
        try markAsAppleCapture(renamedURL, type: "selection")

        let event = await firstEvent(from: stream, timeoutNanoseconds: 3_000_000_000)
        assertScreenshotEvent(event, matches: renamedURL)
    }

    @Test("An app-owned capture is ignored once and unrelated captures still emit")
    func ignoresPublishedAppOwnedCaptureByIdentity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let stagingDirectory = directory.appendingPathComponent(
            ".screenie-stage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let stagedURL = stagingDirectory.appendingPathComponent("capture.png")
        try pngData().write(to: stagedURL)
        try markAsAppleCapture(stagedURL, type: "selection")
        let identity = try #require(ScreenshotFileIdentity.regularFile(at: stagedURL))

        let publishedURL = directory.appendingPathComponent("Screenie capture.png")
        watcher.ignoreNextAppearance(of: identity, at: publishedURL)
        try FileManager.default.moveItem(at: stagedURL, to: publishedURL)
        watcher.finishIgnoredAppearance(
            expectedIdentity: identity,
            observedIdentity: identity,
            at: publishedURL
        )

        try await Task.sleep(nanoseconds: 900_000_000)

        let unrelatedURL = directory.appendingPathComponent("native-selection.png")
        try pngData().write(to: unrelatedURL)
        try markAsAppleCapture(unrelatedURL, type: "selection")
        let unrelatedEvent = await firstEvent(
            from: stream,
            timeoutNanoseconds: 3_000_000_000
        )
        assertScreenshotEvent(unrelatedEvent, matches: unrelatedURL)
    }

    @Test("App-owned path suppression survives an unexpected published inode")
    func ignoresPublishedAppOwnedCaptureByPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = ScreenshotWatcher()
        let (stream, continuation) = try startStream(watcher: watcher, folder: directory)
        defer {
            watcher.stop()
            continuation.finish()
        }

        let stagingDirectory = directory.appendingPathComponent(".path-stage", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        let expectedURL = stagingDirectory.appendingPathComponent("expected-inode.png")
        try pngData().write(to: expectedURL)
        let expectedIdentity = try #require(
            ScreenshotFileIdentity.regularFile(at: expectedURL)
        )
        let publishedURL = directory.appendingPathComponent("Screenie replaced capture.png")
        watcher.ignoreNextAppearance(of: expectedIdentity, at: publishedURL)

        try pngData().write(to: publishedURL)
        try markAsAppleCapture(publishedURL, type: "selection")
        let observedIdentity = try #require(
            ScreenshotFileIdentity.regularFile(at: publishedURL)
        )
        #expect(observedIdentity != expectedIdentity)
        watcher.finishIgnoredAppearance(
            expectedIdentity: expectedIdentity,
            observedIdentity: observedIdentity,
            at: publishedURL
        )

        try await Task.sleep(nanoseconds: 900_000_000)
        let unrelatedURL = directory.appendingPathComponent("later-native-selection.png")
        try pngData().write(to: unrelatedURL)
        try markAsAppleCapture(unrelatedURL, type: "selection")
        let event = await firstEvent(
            from: stream,
            timeoutNanoseconds: 3_000_000_000
        )
        assertScreenshotEvent(event, matches: unrelatedURL)
    }

    private func startStream(
        watcher: ScreenshotWatcher,
        folder: URL
    ) throws -> (AsyncStream<WatchEvent>, AsyncStream<WatchEvent>.Continuation) {
        var capturedContinuation: AsyncStream<WatchEvent>.Continuation?
        let stream = AsyncStream<WatchEvent> { continuation in
            capturedContinuation = continuation
        }
        let continuation = try #require(capturedContinuation)
        try watcher.start(
            folderURL: folder,
            onScreenshot: { continuation.yield(.screenshot($0.url)) },
            onFailure: { continuation.yield(.failure($0.localizedDescription)) }
        )
        return (stream, continuation)
    }

    private func startScreenshotStream(
        watcher: ScreenshotWatcher,
        folder: URL
    ) throws -> (
        AsyncStream<DetectedScreenshot>,
        AsyncStream<DetectedScreenshot>.Continuation
    ) {
        var capturedContinuation: AsyncStream<DetectedScreenshot>.Continuation?
        let stream = AsyncStream<DetectedScreenshot> { continuation in
            capturedContinuation = continuation
        }
        let continuation = try #require(capturedContinuation)
        try watcher.start(
            folderURL: folder,
            onScreenshot: { continuation.yield($0) },
            onFailure: { _ in continuation.finish() }
        )
        return (stream, continuation)
    }

    private func firstEvent(
        from stream: AsyncStream<WatchEvent>,
        timeoutNanoseconds: UInt64
    ) async -> WatchEvent? {
        await withTaskGroup(of: WatchEvent?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let event = await group.next() ?? nil
            group.cancelAll()
            return event
        }
    }

    private func firstScreenshot(
        from stream: AsyncStream<DetectedScreenshot>,
        timeoutNanoseconds: UInt64
    ) async -> DetectedScreenshot? {
        await withTaskGroup(of: DetectedScreenshot?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let screenshot = await group.next() ?? nil
            group.cancelAll()
            return screenshot
        }
    }

    private func assertScreenshotEvent(_ event: WatchEvent?, matches expectedURL: URL) {
        switch event {
        case let .screenshot(detectedURL):
            #expect(
                detectedURL.resolvingSymlinksInPath()
                    == expectedURL.resolvingSymlinksInPath()
            )
        case let .failure(message):
            Issue.record("Watcher failed: \(message)")
        case nil:
            Issue.record("Watcher did not detect the selection before the timeout.")
        }
    }

    private func containsScreenshot(
        _ expectedURL: URL,
        in stream: AsyncStream<WatchEvent>,
        timeoutNanoseconds: UInt64
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await event in stream {
                    if case let .screenshot(url) = event,
                        url.resolvingSymlinksInPath() == expectedURL.resolvingSymlinksInPath()
                    {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let found = await group.next() ?? false
            group.cancelAll()
            return found
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func pngData() throws -> Data {
        try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
    }

    private func markAsAppleCapture(_ url: URL, type: String) throws {
        try setExtendedAttribute(
            named: ScreenshotMetadata.captureMarkerName,
            value: try PropertyListSerialization.data(
                fromPropertyList: true,
                format: .binary,
                options: 0
            ),
            at: url
        )
        try setExtendedAttribute(
            named: ScreenshotMetadata.captureTypeName,
            value: try PropertyListSerialization.data(
                fromPropertyList: type,
                format: .binary,
                options: 0
            ),
            at: url
        )
    }

    private func setExtendedAttribute(named name: String, value: Data, at url: URL) throws {
        let result = value.withUnsafeBytes { bytes in
            url.path.withCString { path in
                name.withCString { attributeName in
                    Darwin.setxattr(
                        path,
                        attributeName,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        XATTR_NOFOLLOW
                    )
                }
            }
        }

        if result != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private final class FailingFirstEnumerationFileManager: FileManager, @unchecked Sendable {
    private(set) var enumerationCount = 0

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        enumerationCount += 1
        if enumerationCount == 1 {
            throw CocoaError(.fileReadUnknown)
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class SkippingFirstEnumerationFileManager: FileManager, @unchecked Sendable {
    private var enumerationCount = 0

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        enumerationCount += 1
        if enumerationCount == 1 {
            return []
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class ReplacingBaselineFolderFileManager: FileManager, @unchecked Sendable {
    private let movedFolder: URL
    private(set) var didReplaceFolder = false

    init(movedFolder: URL) {
        self.movedFolder = movedFolder
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didReplaceFolder {
            didReplaceFolder = true
            try FileManager.default.moveItem(at: url, to: movedFolder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return []
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class CountingEnumerationFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEnumerationCount = 0

    var enumerationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedEnumerationCount
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        lock.lock()
        storedEnumerationCount += 1
        lock.unlock()
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}
