import Darwin
import Foundation
import Testing
@testable import SnapText

@Suite("Apple screenshot metadata")
struct ScreenshotMetadataTests {
    private let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    private let screenCaptureTypeAttribute = "com.apple.metadata:kMDItemScreenCaptureType"

    @Test("Apple selection metadata is recognized")
    func recognizesAppleSelectionScreenshotMetadata() throws {
        let imageURL = try makeTemporaryPNG()
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        try setExtendedAttribute(
            named: screenCaptureAttribute,
            value: try PropertyListSerialization.data(
                fromPropertyList: true,
                format: .binary,
                options: 0
            ),
            at: imageURL
        )
        try setExtendedAttribute(
            named: screenCaptureTypeAttribute,
            value: try PropertyListSerialization.data(
                fromPropertyList: "selection",
                format: .binary,
                options: 0
            ),
            at: imageURL
        )

        #expect(ScreenshotMetadata.isSelectionScreenshot(at: imageURL))
    }

    @Test("Ordinary PNG without Apple metadata is rejected")
    func rejectsOrdinaryPNGWithoutAppleMetadata() throws {
        let imageURL = try makeTemporaryPNG()
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        #expect(!ScreenshotMetadata.isSelectionScreenshot(at: imageURL))
    }

    @Test("Apple capture outside selection mode is rejected")
    func rejectsAppleCaptureThatWasNotASelection() throws {
        let imageURL = try makeTemporaryPNG()
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        try setExtendedAttribute(
            named: screenCaptureAttribute,
            value: try PropertyListSerialization.data(
                fromPropertyList: true,
                format: .binary,
                options: 0
            ),
            at: imageURL
        )
        try setExtendedAttribute(
            named: screenCaptureTypeAttribute,
            value: try PropertyListSerialization.data(
                fromPropertyList: "window",
                format: .binary,
                options: 0
            ),
            at: imageURL
        )

        #expect(!ScreenshotMetadata.isSelectionScreenshot(at: imageURL))
    }

    private func makeTemporaryPNG() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("selection.png")
        let png = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        try png.write(to: url, options: .atomic)
        return url
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
