import Foundation
import Testing
@testable import SnapText

@Suite("Screenshot image loader")
struct ScreenshotImageLoaderTests {
    @Test("PNG bytes and MIME type are preserved")
    func preservesPNG() throws {
        let sourceData = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let imageURL = try writeTemporaryImage(sourceData, extension: "png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let payload = try ScreenshotImageLoader.load(from: imageURL)

        #expect(payload.mimeType == "image/png")
        #expect(payload.data == sourceData)
    }

    @Test("JPEG bytes and MIME type are preserved")
    func preservesJPEG() throws {
        let sourceData = try #require(
            Data(
                base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBARXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAgEBAgMCAgIDBAMDAwMEBgQEBAQEBgcGBgYGBgYHBwcHBwcHBwgICAgICAkJCQkJCwsLCwsLCwsLC//bAEMBAgICAwMDBQMDBQsIBggLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC//dAAQAAf/aAAwDAQACEQMRAD8A/v4ooooA/9k="
            )
        )
        let imageURL = try writeTemporaryImage(sourceData, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let payload = try ScreenshotImageLoader.load(from: imageURL)

        #expect(payload.mimeType == "image/jpeg")
        #expect(payload.data == sourceData)
    }

    @Test("Automatic load requires selection metadata on the opened file")
    func requiresSelectionMetadata() throws {
        let sourceData = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let imageURL = try writeTemporaryImage(sourceData, extension: "png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        do {
            _ = try ScreenshotImageLoader.load(
                from: imageURL,
                requiresSelectionMetadata: true
            )
            Issue.record("Expected missing selection metadata to reject the image.")
        } catch ScreenshotImageLoadError.missingSelectionMetadata {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Expected inode mismatch rejects a replaced path")
    func rejectsIdentityMismatch() throws {
        let sourceData = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let imageURL = try writeTemporaryImage(sourceData, extension: "png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        do {
            _ = try ScreenshotImageLoader.load(
                from: imageURL,
                expectedIdentity: ScreenshotFileIdentity(device: 0, inode: 0)
            )
            Issue.record("Expected an inode mismatch to reject the image.")
        } catch ScreenshotImageLoadError.changedBeforeRead {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Symbolic links are not followed")
    func rejectsSymbolicLink() throws {
        let sourceData = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let imageURL = try writeTemporaryImage(sourceData, extension: "png")
        let linkURL = imageURL.deletingLastPathComponent().appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        do {
            _ = try ScreenshotImageLoader.load(from: linkURL)
            Issue.record("Expected O_NOFOLLOW to reject the symbolic link.")
        } catch ScreenshotImageLoadError.unreadable {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Files over the app byte cap are rejected before decoding")
    func rejectsOversizedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("oversized.png")
        FileManager.default.createFile(atPath: imageURL.path, contents: Data([0]))
        let handle = try FileHandle(forWritingTo: imageURL)
        try handle.truncate(atOffset: UInt64(AppConfiguration.maximumInputBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try ScreenshotImageLoader.load(from: imageURL)
            Issue.record("Expected the byte cap to reject the file.")
        } catch ScreenshotImageLoadError.fileTooLarge {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func writeTemporaryImage(_ data: Data, extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
