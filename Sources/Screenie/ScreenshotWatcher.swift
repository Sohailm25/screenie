import Darwin
import Foundation
import ImageIO

enum ScreenshotMetadata {
    enum CaptureKind {
        case selection
        case otherCapture
        case unresolved
    }

    static let captureMarkerName = "com.apple.metadata:kMDItemIsScreenCapture"
    static let captureTypeName = "com.apple.metadata:kMDItemScreenCaptureType"

    static func isSelectionScreenshot(at url: URL) -> Bool {
        captureKind(at: url) == .selection
    }

    static func captureKind(at url: URL) -> CaptureKind {
        captureKind(
            marker: extendedAttribute(named: captureMarkerName, at: url),
            typeData: extendedAttribute(named: captureTypeName, at: url)
        )
    }

    static func captureKind(fileDescriptor: Int32) -> CaptureKind {
        captureKind(
            marker: extendedAttribute(named: captureMarkerName, fileDescriptor: fileDescriptor),
            typeData: extendedAttribute(named: captureTypeName, fileDescriptor: fileDescriptor)
        )
    }

    private static func captureKind(marker: Data?, typeData: Data?) -> CaptureKind {
        guard let marker else { return .unresolved }
        guard markerRepresentsTrue(marker) else { return .otherCapture }
        guard let typeData else { return .unresolved }

        if let captureType = propertyListValue(from: typeData) as? String {
            return captureType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "selection" ? .selection : .otherCapture
        }

        let selectionBytes = Data("selection".utf8)
        return typeData.range(of: selectionBytes) == nil ? .otherCapture : .selection
    }

    static func extendedAttribute(named name: String, at url: URL) -> Data? {
        let path = url.path
        let length = path.withCString { pathPointer in
            name.withCString { namePointer in
                getxattr(pathPointer, namePointer, nil, 0, 0, XATTR_NOFOLLOW)
            }
        }
        guard length >= 0 else { return nil }
        guard length > 0 else { return Data() }

        var data = Data(count: length)
        let bytesRead = data.withUnsafeMutableBytes { buffer in
            path.withCString { pathPointer in
                name.withCString { namePointer in
                    getxattr(
                        pathPointer,
                        namePointer,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        XATTR_NOFOLLOW
                    )
                }
            }
        }
        guard bytesRead == length else { return nil }
        return data
    }

    private static func extendedAttribute(named name: String, fileDescriptor: Int32) -> Data? {
        let length = name.withCString { namePointer in
            fgetxattr(fileDescriptor, namePointer, nil, 0, 0, 0)
        }
        guard length >= 0 else { return nil }
        guard length > 0 else { return Data() }

        var data = Data(count: length)
        let bytesRead = data.withUnsafeMutableBytes { buffer in
            name.withCString { namePointer in
                fgetxattr(
                    fileDescriptor,
                    namePointer,
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    0
                )
            }
        }
        guard bytesRead == length else { return nil }
        return data
    }

    private static func markerRepresentsTrue(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        guard let value = propertyListValue(from: data) else { return true }
        if let boolean = value as? Bool {
            return boolean
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return true
    }

    private static func propertyListValue(from data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}

enum ScreenshotWatcherError: LocalizedError {
    case cannotOpenFolder(URL)
    case folderBecameUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case let .cannotOpenFolder(url):
            return "Screenie could not watch the screenshot folder: \(url.path)"
        case let .folderBecameUnavailable(url):
            return "The watched screenshot folder moved or became unavailable: \(url.path)"
        }
    }
}

struct ScreenshotFileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64

    static func regularFile(at url: URL) -> ScreenshotFileIdentity? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &information)
        }
        guard
            result == 0,
            (information.st_mode & S_IFMT) == S_IFREG
        else { return nil }
        return ScreenshotFileIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }
}

struct DetectedScreenshot: Sendable {
    let url: URL
    let identity: ScreenshotFileIdentity
    let modificationDate: Date
    let discoverySequence: UInt64
}

// All mutable watcher state is confined to queue. Public entry points synchronize with it.
final class ScreenshotWatcher: @unchecked Sendable {
    typealias ScreenshotHandler = (DetectedScreenshot) -> Void
    typealias FailureHandler = (Error) -> Void

    private let queue = DispatchQueue(label: "com.sohailmohammad.Screenie.screenshot-watcher")
    private let queueKey = DispatchSpecificKey<Void>()
    private let fileManager: FileManager
    private var source: DispatchSourceFileSystemObject?
    private var folderURL: URL?
    private var folderIdentity: DirectoryIdentity?
    private var knownFiles = Set<ScreenshotFileIdentity>()
    private var ignoredAppearances = Set<ScreenshotFileIdentity>()
    private var ignoredAppearancePaths = Set<String>()
    private var pendingFiles: [ScreenshotFileIdentity: URL] = [:]
    private var candidateSnapshots: [ScreenshotFileIdentity: FileSnapshot] = [:]
    private var candidateSequence: UInt64 = 0
    private var newestProcessedSequence: UInt64 = 0
    private var screenshotHandler: ScreenshotHandler?
    private var failureHandler: FailureHandler?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    func start(
        folderURL: URL,
        onScreenshot: @escaping ScreenshotHandler,
        onFailure: @escaping FailureHandler
    ) throws {
        try syncOnQueue {
            stopOnQueue()
            let descriptor = folderURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return open(path, O_EVTONLY | O_CLOEXEC)
            }
            guard descriptor >= 0 else {
                throw ScreenshotWatcherError.cannotOpenFolder(folderURL)
            }
            var ownsDescriptor = true
            defer {
                if ownsDescriptor {
                    close(descriptor)
                }
            }

            guard
                let openedFolderIdentity = Self.directoryIdentity(fileDescriptor: descriptor),
                Self.directoryIdentity(at: folderURL) == openedFolderIdentity
            else {
                throw ScreenshotWatcherError.cannotOpenFolder(folderURL)
            }
            let baseline = Set(try contents(of: folderURL).compactMap(Self.identity))
            guard Self.directoryIdentity(at: folderURL) == openedFolderIdentity else {
                throw ScreenshotWatcherError.folderBecameUnavailable(folderURL)
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                let flags = source.data
                if !flags.intersection([.rename, .delete, .revoke]).isEmpty {
                    self.reportUnavailableFolder()
                    return
                }
                self.scanForChanges()
                self.queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.scanForChanges()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.setRegistrationHandler { [weak self] in
                self?.scanForChanges()
            }

            self.folderURL = folderURL
            folderIdentity = openedFolderIdentity
            screenshotHandler = onScreenshot
            failureHandler = onFailure
            knownFiles = baseline
            pendingFiles.removeAll()
            candidateSnapshots.removeAll()
            candidateSequence = 0
            newestProcessedSequence = 0
            self.source = source
            ownsDescriptor = false
            source.resume()
            scanForChanges()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync {
                stopOnQueue()
            }
        }
    }

    // App-owned captures are created in a hidden staging directory. Registering the
    // inode before publishing it into the watched folder prevents a second upload.
    func ignoreNextAppearance(of identity: ScreenshotFileIdentity, at url: URL) {
        syncOnQueue {
            _ = ignoredAppearances.insert(identity)
            _ = ignoredAppearancePaths.insert(Self.normalizedPath(url))
        }
    }

    func cancelIgnoredAppearance(of identity: ScreenshotFileIdentity, at url: URL) {
        syncOnQueue {
            _ = ignoredAppearances.remove(identity)
            _ = ignoredAppearancePaths.remove(Self.normalizedPath(url))
        }
    }

    func finishIgnoredAppearance(
        expectedIdentity: ScreenshotFileIdentity,
        observedIdentity: ScreenshotFileIdentity,
        at url: URL
    ) {
        syncOnQueue {
            _ = ignoredAppearances.remove(expectedIdentity)
            _ = ignoredAppearancePaths.remove(Self.normalizedPath(url))
            knownFiles.insert(observedIdentity)
            pendingFiles.removeValue(forKey: expectedIdentity)
            pendingFiles.removeValue(forKey: observedIdentity)
            candidateSnapshots.removeValue(forKey: expectedIdentity)
            candidateSnapshots.removeValue(forKey: observedIdentity)
        }
    }

    // Force a scan before taking the boundary so callbacks already in flight
    // cannot overtake a direct shortcut capture on the main actor.
    func captureOrderingBoundary() -> UInt64 {
        syncOnQueue {
            scanForChanges()
            return candidateSequence
        }
    }

    private func syncOnQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        } else {
            return try queue.sync(execute: body)
        }
    }

    private func stopOnQueue() {
        source?.cancel()
        source = nil
        folderURL = nil
        folderIdentity = nil
        knownFiles.removeAll()
        ignoredAppearances.removeAll()
        ignoredAppearancePaths.removeAll()
        pendingFiles.removeAll()
        candidateSnapshots.removeAll()
        screenshotHandler = nil
        failureHandler = nil
    }

    static func latestSelectionScreenshot(
        in folderURL: URL,
        fileManager: FileManager = .default
    ) -> DetectedScreenshot? {
        latestImage(in: folderURL, fileManager: fileManager) {
            ScreenshotMetadata.isSelectionScreenshot(at: $0)
        }
    }

    static func latestScreenshot(
        in folderURL: URL,
        fileManager: FileManager = .default
    ) -> DetectedScreenshot? {
        latestImage(in: folderURL, fileManager: fileManager) { _ in true }
    }

    private static func latestImage(
        in folderURL: URL,
        fileManager: FileManager,
        matching predicate: (URL) -> Bool
    ) -> DetectedScreenshot? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter { isSupportedImage($0) && predicate($0) }
            .compactMap { url -> (DetectedScreenshot, Date)? in
                guard
                    let identity = identity(url),
                    let snapshot = snapshot(url),
                    snapshot.size > 0
                else { return nil }
                return (
                    DetectedScreenshot(
                        url: url,
                        identity: identity,
                        modificationDate: snapshot.modificationDate,
                        discoverySequence: 0
                    ),
                    snapshot.modificationDate
                )
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func scanForChanges() {
        guard
            let folderURL,
            let folderIdentity,
            Self.directoryIdentity(at: folderURL) == folderIdentity
        else {
            if self.folderURL != nil {
                reportUnavailableFolder()
            }
            return
        }
        guard let urls = try? contents(of: folderURL) else {
            reportUnavailableFolder()
            return
        }
        guard Self.directoryIdentity(at: folderURL) == folderIdentity else {
            reportUnavailableFolder()
            return
        }

        let supported = urls.compactMap { url -> DiscoveredFile? in
            guard
                Self.isSupportedImage(url),
                let identity = Self.identity(url)
            else { return nil }
            return DiscoveredFile(identity: identity, url: url, snapshot: Self.snapshot(url))
        }
        let currentIdentities = Set(supported.map(\.identity))
        let appearedIgnoredFiles = supported.filter {
            ignoredAppearances.contains($0.identity)
                || ignoredAppearancePaths.contains(Self.normalizedPath($0.url))
        }
        for file in appearedIgnoredFiles {
            ignoredAppearances.remove(file.identity)
            ignoredAppearancePaths.remove(Self.normalizedPath(file.url))
            knownFiles.insert(file.identity)
            pendingFiles.removeValue(forKey: file.identity)
            candidateSnapshots.removeValue(forKey: file.identity)
        }
        knownFiles.formIntersection(currentIdentities)
        pendingFiles = pendingFiles.filter { currentIdentities.contains($0.key) }
        candidateSnapshots = candidateSnapshots.filter { currentIdentities.contains($0.key) }
        for file in supported where pendingFiles[file.identity] != nil {
            pendingFiles[file.identity] = file.url
        }

        let newlyDiscovered = supported.filter {
            !knownFiles.contains($0.identity) && pendingFiles[$0.identity] == nil
        }
        let newCandidates = newlyDiscovered
            .sorted {
                let leftDate = $0.snapshot?.modificationDate ?? .distantPast
                let rightDate = $1.snapshot?.modificationDate ?? .distantPast
                if leftDate == rightDate {
                    return $0.url.path < $1.url.path
                }
                return leftDate < rightDate
            }
            .map { discovered -> Candidate in
                candidateSequence &+= 1
                return Candidate(
                    identity: discovered.identity,
                    url: discovered.url,
                    sequence: candidateSequence
                )
            }
        let confirmedSelections = newCandidates
            .filter { ScreenshotMetadata.captureKind(at: $0.url) == .selection }

        if let newest = confirmedSelections.last {
            for older in confirmedSelections.dropLast() {
                knownFiles.insert(older.identity)
            }
            pendingFiles[newest.identity] = newest.url
            inspect(newest, attempt: 0)
        }

        let confirmedIdentities = Set(confirmedSelections.map(\.identity))
        for candidate in newCandidates where !confirmedIdentities.contains(candidate.identity) {
            pendingFiles[candidate.identity] = candidate.url
            inspect(candidate, attempt: 0)
        }
    }

    private func inspect(_ candidate: Candidate, attempt: Int) {
        let delay = attempt == 0 ? 0.035 : min(0.04 * Double(attempt), 0.2)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard
                let self,
                let folderURL = self.folderURL,
                let folderIdentity = self.folderIdentity,
                Self.directoryIdentity(at: folderURL) == folderIdentity
            else {
                if self?.folderURL != nil {
                    self?.reportUnavailableFolder()
                }
                return
            }
            let identity = candidate.identity
            guard var url = self.pendingFiles[identity] else { return }

            if
                !self.fileManager.fileExists(atPath: url.path)
                    || Self.identity(url) != identity
            {
                self.scanForChanges()
                guard
                    let updatedURL = self.pendingFiles[identity],
                    Self.identity(updatedURL) == identity
                else { return }
                url = updatedURL
            }

            switch ScreenshotMetadata.captureKind(at: url) {
            case .otherCapture:
                self.finishCandidate(identity)
                return
            case .unresolved:
                break
            case .selection:
                if
                    let currentSnapshot = Self.snapshot(url),
                    currentSnapshot.size > 0,
                    self.candidateSnapshots[identity] == currentSnapshot
                {
                    if currentSnapshot.size > AppConfiguration.maximumInputBytes
                        || Self.isReadableImage(url)
                    {
                        self.emit(candidate, at: url)
                        return
                    }
                }
                self.candidateSnapshots[identity] = Self.snapshot(url)
            }

            if attempt < 10 {
                self.inspect(candidate, attempt: attempt + 1)
            } else {
                self.finishCandidate(identity)
            }
        }
    }

    private func finishCandidate(_ identity: ScreenshotFileIdentity) {
        pendingFiles.removeValue(forKey: identity)
        candidateSnapshots.removeValue(forKey: identity)
        knownFiles.insert(identity)
    }

    private func emit(_ candidate: Candidate, at url: URL) {
        finishCandidate(candidate.identity)
        guard candidate.sequence > newestProcessedSequence else { return }
        newestProcessedSequence = candidate.sequence
        screenshotHandler?(
            DetectedScreenshot(
                url: url,
                identity: candidate.identity,
                modificationDate: Self.snapshot(url)?.modificationDate ?? .distantPast,
                discoverySequence: candidate.sequence
            )
        )
    }

    private func reportUnavailableFolder() {
        guard let folderURL else { return }
        let error = ScreenshotWatcherError.folderBecameUnavailable(folderURL)
        let callback = failureHandler
        stopOnQueue()
        callback?(error)
    }

    private func contents(of folderURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    private static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
            && CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
            .contains(url.pathExtension.lowercased())
    }

    private static func identity(_ url: URL) -> ScreenshotFileIdentity? {
        ScreenshotFileIdentity.regularFile(at: url)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func directoryIdentity(at url: URL) -> DirectoryIdentity? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return fstatat(AT_FDCWD, path, &information, 0)
        }
        guard
            result == 0,
            (information.st_mode & S_IFMT) == S_IFDIR
        else { return nil }
        return DirectoryIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    private static func directoryIdentity(fileDescriptor: Int32) -> DirectoryIdentity? {
        var information = stat()
        guard
            fstat(fileDescriptor, &information) == 0,
            (information.st_mode & S_IFMT) == S_IFDIR
        else { return nil }
        return DirectoryIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    private static func snapshot(_ url: URL) -> FileSnapshot? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &information)
        }
        guard
            result == 0,
            (information.st_mode & S_IFMT) == S_IFREG,
            information.st_size >= 0
        else { return nil }

        let modificationTime = TimeInterval(information.st_mtimespec.tv_sec)
            + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileSnapshot(
            size: Int(information.st_size),
            modificationDate: Date(timeIntervalSince1970: modificationTime)
        )
    }
}

private struct DirectoryIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
}

private struct FileSnapshot: Equatable {
    let size: Int
    let modificationDate: Date
}

private struct DiscoveredFile {
    let identity: ScreenshotFileIdentity
    let url: URL
    let snapshot: FileSnapshot?
}

private struct Candidate {
    let identity: ScreenshotFileIdentity
    let url: URL
    let sequence: UInt64
}
