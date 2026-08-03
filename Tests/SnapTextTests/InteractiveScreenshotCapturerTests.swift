import Darwin
import Foundation
import Testing
@testable import SnapText

@Suite("Interactive screenshot capture", .serialized)
struct InteractiveScreenshotCapturerTests {
    @Test("Capture invokes Apple's selector with an exact output path and scrubbed environment")
    func invokesExpectedCommand() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("capture.png")
        let executor = RecordingScreenshotProcessExecutor(
            exitStatus: 0,
            output: .file(Data([0x89, 0x50, 0x4E, 0x47]))
        )
        let capturer = InteractiveScreenshotCapturer(processExecutor: executor)

        let result = try await capturer.capture(to: outputURL)

        let request = try #require(await executor.requests.first)
        #expect(request.executableURL.path == "/usr/sbin/screencapture")
        #expect(request.arguments == ["-i", "-s", "-t", "png", outputURL.path])
        #expect(request.environment == InteractiveScreenshotCapturer.processEnvironment)
        #expect(request.environment.keys.sorted() == ["LANG", "PATH"])

        let expectedIdentity = try #require(fileIdentity(at: outputURL))
        #expect(result == .captured(expectedIdentity))
    }

    @Test("A successful command with no output file is a cancelled capture")
    func missingOutputIsCancelled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("missing.png")
        let executor = RecordingScreenshotProcessExecutor(exitStatus: 0, output: .none)

        let result = try await InteractiveScreenshotCapturer(processExecutor: executor)
            .capture(to: outputURL)

        #expect(result == .cancelled)
    }

    @Test("A nonzero exit without output remains compatible with Escape cancellation")
    func nonzeroMissingOutputIsCancelled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("cancelled.png")
        let executor = RecordingScreenshotProcessExecutor(exitStatus: 1, output: .none)

        let result = try await InteractiveScreenshotCapturer(processExecutor: executor)
            .capture(to: outputURL)

        #expect(result == .cancelled)
    }

    @Test("A nonzero command exit with output is reported as a failure")
    func commandFailureWithOutputIsReported() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("failed.png")
        let executor = RecordingScreenshotProcessExecutor(
            exitStatus: 2,
            output: .file(Data([0x89, 0x50, 0x4E, 0x47]))
        )

        do {
            _ = try await InteractiveScreenshotCapturer(processExecutor: executor)
                .capture(to: outputURL)
            Issue.record("Expected the command failure to be reported.")
        } catch let error as InteractiveScreenshotCaptureError {
            #expect(error == .captureCommandFailed(2))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Empty files and directories are not successful captures", arguments: [
        SimulatedOutput.emptyFile,
        SimulatedOutput.directory,
    ])
    func rejectsInvalidOutput(output: SimulatedOutput) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("invalid.png")
        let executor = RecordingScreenshotProcessExecutor(exitStatus: 0, output: output)

        do {
            _ = try await InteractiveScreenshotCapturer(processExecutor: executor)
                .capture(to: outputURL)
            Issue.record("Expected invalid output to be rejected.")
        } catch let error as InteractiveScreenshotCaptureError {
            #expect(error == .invalidCaptureOutput)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("An existing destination is never passed to the capture process")
    func refusesExistingDestination() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("existing.png")
        let original = Data("existing screenshot".utf8)
        try original.write(to: outputURL)
        let executor = RecordingScreenshotProcessExecutor(
            exitStatus: 0,
            output: .file(Data("replacement".utf8))
        )

        do {
            _ = try await InteractiveScreenshotCapturer(processExecutor: executor)
                .capture(to: outputURL)
            Issue.record("Expected an existing destination to be rejected.")
        } catch let error as InteractiveScreenshotCaptureError {
            #expect(error == .destinationAlreadyExists(outputURL))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await executor.requests.isEmpty)
        #expect(try Data(contentsOf: outputURL) == original)
    }

    @Test("Destination helper returns distinct PNG paths inside the chosen folder")
    func createsUniqueDestinations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifiers = IdentifierSequence([
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        ])
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try ScreenshotCaptureDestination.makeUniquePNGURL(
            in: directory,
            date: date,
            identifierProvider: { identifiers.next() }
        )
        let second = try ScreenshotCaptureDestination.makeUniquePNGURL(
            in: directory,
            date: date,
            identifierProvider: { identifiers.next() }
        )

        #expect(first.deletingLastPathComponent() == directory)
        #expect(second.deletingLastPathComponent() == directory)
        #expect(first.pathExtension == "png")
        #expect(second.pathExtension == "png")
        #expect(first != second)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Capture workspace is hidden, private, and removable")
    func createsPrivateCaptureWorkspace() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        let workspace = try ScreenshotCaptureWorkspace.create(
            in: directory,
            identifier: identifier
        )

        #expect(workspace.directoryURL.deletingLastPathComponent() == directory)
        #expect(workspace.directoryURL.lastPathComponent.hasPrefix(".snaptext-capture-"))
        #expect(workspace.captureURL.deletingLastPathComponent() == workspace.directoryURL)
        var information = stat()
        #expect(lstat(workspace.directoryURL.path, &information) == 0)
        #expect((information.st_mode & S_IFMT) == S_IFDIR)
        #expect((information.st_mode & 0o777) == 0o700)

        workspace.remove()
        #expect(!FileManager.default.fileExists(atPath: workspace.directoryURL.path))
    }

    @Test("Workspace cleanup does not remove a replacement directory")
    func cleanupRejectsReplacedDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try ScreenshotCaptureWorkspace.create(in: directory)
        let movedURL = directory.appendingPathComponent("moved-original", isDirectory: true)
        try FileManager.default.moveItem(at: workspace.directoryURL, to: movedURL)
        try FileManager.default.createDirectory(
            at: workspace.directoryURL,
            withIntermediateDirectories: false
        )
        let sentinelURL = workspace.directoryURL.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinelURL)

        workspace.remove()

        #expect(FileManager.default.fileExists(atPath: sentinelURL.path))
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
    }

    @Test("Destination collisions do not overwrite an existing file")
    func collisionDoesNotOverwrite() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let candidate = try ScreenshotCaptureDestination.makeUniquePNGURL(
            in: directory,
            date: date,
            identifierProvider: { identifier }
        )
        let original = Data("keep this file".utf8)
        try original.write(to: candidate)

        do {
            _ = try ScreenshotCaptureDestination.makeUniquePNGURL(
                in: directory,
                date: date,
                identifierProvider: { identifier }
            )
            Issue.record("Expected repeated identifiers to exhaust the unique-name attempts.")
        } catch let error as InteractiveScreenshotCaptureError {
            #expect(error == .unableToCreateUniqueDestination(directory))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: candidate) == original)
    }

    @Test("Cancelling process execution terminates and joins the child")
    func cancellationTerminatesChild() async throws {
        let (processes, continuation) = AsyncStream<Int32>.makeStream()
        let executor = FoundationScreenshotProcessExecutor { processID in
            continuation.yield(processID)
        }
        let task = Task {
            try await executor.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                environment: [:]
            )
        }
        var iterator = processes.makeAsyncIterator()
        let processID = try #require(await iterator.next())

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected process execution to throw CancellationError.")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        continuation.finish()

        errno = 0
        #expect(kill(processID, 0) == -1)
        #expect(errno == ESRCH)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileIdentity(at url: URL) -> ScreenshotFileIdentity? {
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

private struct ScreenshotProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
}

enum SimulatedOutput: Sendable {
    case none
    case emptyFile
    case file(Data)
    case directory
}

private actor RecordingScreenshotProcessExecutor: ScreenshotProcessExecuting {
    let exitStatus: Int32
    let output: SimulatedOutput
    private(set) var requests: [ScreenshotProcessRequest] = []

    init(exitStatus: Int32, output: SimulatedOutput) {
        self.exitStatus = exitStatus
        self.output = output
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> Int32 {
        requests.append(
            ScreenshotProcessRequest(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment
            )
        )

        guard let outputPath = arguments.last else { return exitStatus }
        let outputURL = URL(fileURLWithPath: outputPath)
        switch output {
        case .none:
            break
        case .emptyFile:
            FileManager.default.createFile(atPath: outputPath, contents: Data())
        case let .file(data):
            try data.write(to: outputURL)
        case .directory:
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: false
            )
        }
        return exitStatus
    }
}

private final class IdentifierSequence: @unchecked Sendable {
    private var identifiers: [UUID]
    private let lock = NSLock()

    init(_ identifiers: [UUID]) {
        self.identifiers = identifiers
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.removeFirst()
    }
}
