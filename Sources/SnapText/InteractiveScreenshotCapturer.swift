import Darwin
import Foundation

enum InteractiveScreenshotCaptureResult: Equatable, Sendable {
    case captured(ScreenshotFileIdentity)
    case cancelled
}

enum InteractiveScreenshotCaptureError: LocalizedError, Equatable {
    case destinationAlreadyExists(URL)
    case destinationFolderUnavailable(URL)
    case captureCommandFailed(Int32)
    case invalidCaptureOutput
    case unableToCreatePrivateWorkspace(URL)
    case unableToCreateUniqueDestination(URL)

    var errorDescription: String? {
        switch self {
        case let .destinationAlreadyExists(url):
            return "SnapText will not overwrite the existing file at \(url.path)."
        case let .destinationFolderUnavailable(url):
            return "The screenshot folder is unavailable: \(url.path)"
        case let .captureCommandFailed(status):
            return "Apple’s screenshot tool failed (exit status \(status))."
        case .invalidCaptureOutput:
            return "Apple’s screenshot tool produced an invalid output file."
        case let .unableToCreatePrivateWorkspace(url):
            return "SnapText could not create a private capture workspace in \(url.path)."
        case let .unableToCreateUniqueDestination(url):
            return "SnapText could not choose a unique screenshot name in \(url.path)."
        }
    }
}

struct ScreenshotCaptureWorkspace: Sendable {
    let directoryURL: URL
    let captureURL: URL
    private let device: UInt64
    private let inode: UInt64

    static func create(
        in folderURL: URL,
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> ScreenshotCaptureWorkspace {
        let directoryURL = folderURL.appendingPathComponent(
            ".snaptext-capture-\(identifier.uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw InteractiveScreenshotCaptureError
                .unableToCreatePrivateWorkspace(folderURL)
        }

        guard let identity = directoryIdentity(at: directoryURL) else {
            try? fileManager.removeItem(at: directoryURL)
            throw InteractiveScreenshotCaptureError
                .unableToCreatePrivateWorkspace(folderURL)
        }

        return ScreenshotCaptureWorkspace(
            directoryURL: directoryURL,
            captureURL: directoryURL.appendingPathComponent("capture.png"),
            device: identity.device,
            inode: identity.inode
        )
    }

    func remove(fileManager: FileManager = .default) {
        guard
            let identity = Self.directoryIdentity(at: directoryURL),
            identity.device == device,
            identity.inode == inode
        else { return }
        try? fileManager.removeItem(at: directoryURL)
    }

    private static func directoryIdentity(
        at url: URL
    ) -> (device: UInt64, inode: UInt64)? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &information)
        }
        guard
            result == 0,
            (information.st_mode & S_IFMT) == S_IFDIR
        else { return nil }
        return (UInt64(information.st_dev), UInt64(information.st_ino))
    }
}

protocol ScreenshotProcessExecuting: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> Int32
}

struct FoundationScreenshotProcessExecutor: ScreenshotProcessExecuting {
    private let didStart: @Sendable (Int32) -> Void

    init(didStart: @escaping @Sendable (Int32) -> Void = { _ in }) {
        self.didStart = didStart
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> Int32 {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        didStart(process.processIdentifier)

        let runningProcess = RunningProcess(process)
        return try await withTaskCancellationHandler {
            let status = await Task.detached(priority: .userInitiated) {
                runningProcess.waitUntilExit()
            }.value
            try Task.checkCancellation()
            return status
        } onCancel: {
            runningProcess.terminate()
        }
    }
}

struct InteractiveScreenshotCapturer: Sendable {
    static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    static let processEnvironment = [
        "LANG": "C",
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]

    private let processExecutor: any ScreenshotProcessExecuting

    init(
        processExecutor: any ScreenshotProcessExecuting = FoundationScreenshotProcessExecutor()
    ) {
        self.processExecutor = processExecutor
    }

    func capture(to outputURL: URL) async throws -> InteractiveScreenshotCaptureResult {
        try Task.checkCancellation()
        guard !Self.pathExistsWithoutFollowingSymbolicLinks(outputURL) else {
            throw InteractiveScreenshotCaptureError.destinationAlreadyExists(outputURL)
        }

        let status = try await processExecutor.run(
            executableURL: Self.executableURL,
            arguments: ["-i", "-s", "-t", "png", outputURL.path],
            environment: Self.processEnvironment
        )
        try Task.checkCancellation()

        guard Self.pathExistsWithoutFollowingSymbolicLinks(outputURL) else {
            return .cancelled
        }
        guard status == 0 else {
            throw InteractiveScreenshotCaptureError.captureCommandFailed(status)
        }
        guard let identity = Self.completedCaptureIdentity(at: outputURL) else {
            throw InteractiveScreenshotCaptureError.invalidCaptureOutput
        }
        return .captured(identity)
    }

    static func pathExistsWithoutFollowingSymbolicLinks(_ url: URL) -> Bool {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &information)
        }
        return result == 0 || errno != ENOENT
    }

    static func completedCaptureIdentity(
        at url: URL
    ) -> ScreenshotFileIdentity? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &information)
        }
        guard
            result == 0,
            (information.st_mode & S_IFMT) == S_IFREG,
            information.st_size > 0
        else { return nil }

        return ScreenshotFileIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }
}

enum ScreenshotCaptureDestination {
    static func makeUniquePNGURL(
        in folderURL: URL,
        date: Date = Date(),
        identifierProvider: () -> UUID = { UUID() }
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: folderURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw InteractiveScreenshotCaptureError.destinationFolderUnavailable(folderURL)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let timestamp = formatter.string(from: date)

        for _ in 0..<32 {
            let identifier = identifierProvider().uuidString
            let filename = "SnapText \(timestamp) \(identifier).png"
            let candidate = folderURL.appendingPathComponent(filename, isDirectory: false)
            guard !InteractiveScreenshotCapturer.pathExistsWithoutFollowingSymbolicLinks(candidate)
            else { continue }
            return candidate
        }

        throw InteractiveScreenshotCaptureError.unableToCreateUniqueDestination(folderURL)
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func waitUntilExit() -> Int32 {
        process.waitUntilExit()
        return process.terminationStatus
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}
