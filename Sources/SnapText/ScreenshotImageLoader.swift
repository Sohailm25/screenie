import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotImagePayload: Sendable {
    let data: Data
    let mimeType: String
}

enum ScreenshotImageLoadError: LocalizedError {
    case unreadable
    case changedBeforeRead
    case missingSelectionMetadata
    case fileTooLarge
    case dimensionsTooLarge
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The screenshot image could not be read."
        case .changedBeforeRead:
            return "The screenshot changed before SnapText could read it."
        case .missingSelectionMetadata:
            return "The detected file no longer has Apple selection-screenshot metadata."
        case .fileTooLarge:
            return "The image exceeds SnapText’s 16 MiB safety cap."
        case .dimensionsTooLarge:
            return "The image exceeds SnapText’s 64-megapixel or 16,384-pixel-side safety cap."
        case .conversionFailed:
            return "The screenshot image could not be converted to PNG."
        }
    }
}

enum ScreenshotImageLoader {
    static func load(
        from url: URL,
        expectedIdentity: ScreenshotFileIdentity? = nil,
        requiresSelectionMetadata: Bool = false
    ) throws -> ScreenshotImagePayload {
        try Task.checkCancellation()
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ScreenshotImageLoadError.unreadable
        }
        defer { close(descriptor) }

        var before = stat()
        guard
            fstat(descriptor, &before) == 0,
            (before.st_mode & S_IFMT) == S_IFREG,
            before.st_size > 0
        else {
            throw ScreenshotImageLoadError.unreadable
        }

        let openedIdentity = ScreenshotFileIdentity(
            device: UInt64(before.st_dev),
            inode: UInt64(before.st_ino)
        )
        if let expectedIdentity, expectedIdentity != openedIdentity {
            throw ScreenshotImageLoadError.changedBeforeRead
        }
        guard before.st_size <= AppConfiguration.maximumInputBytes else {
            throw ScreenshotImageLoadError.fileTooLarge
        }

        let data = try readAll(from: descriptor, expectedSize: Int(before.st_size))
        try Task.checkCancellation()

        var after = stat()
        guard
            fstat(descriptor, &after) == 0,
            ScreenshotFileIdentity(
                device: UInt64(after.st_dev),
                inode: UInt64(after.st_ino)
            ) == openedIdentity,
            after.st_size == before.st_size,
            after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
            after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
            data.count == Int(after.st_size)
        else {
            throw ScreenshotImageLoadError.changedBeforeRead
        }

        if requiresSelectionMetadata,
            ScreenshotMetadata.captureKind(fileDescriptor: descriptor) != .selection
        {
            throw ScreenshotImageLoadError.missingSelectionMetadata
        }

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let typeIdentifier = CGImageSourceGetType(source) as String?
        else {
            throw ScreenshotImageLoadError.unreadable
        }
        guard dimensionsAreWithinLimits(source) else {
            throw ScreenshotImageLoadError.dimensionsTooLarge
        }
        try Task.checkCancellation()

        if UTType(typeIdentifier)?.conforms(to: .png) == true {
            return ScreenshotImagePayload(data: data, mimeType: "image/png")
        }
        if UTType(typeIdentifier)?.conforms(to: .jpeg) == true {
            return ScreenshotImagePayload(data: data, mimeType: "image/jpeg")
        }

        let converted = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            converted as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotImageLoadError.conversionFailed
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotImageLoadError.conversionFailed
        }
        guard converted.length <= AppConfiguration.maximumInputBytes else {
            throw ScreenshotImageLoadError.fileTooLarge
        }
        return ScreenshotImagePayload(data: converted as Data, mimeType: "image/png")
    }

    private static func readAll(from descriptor: Int32, expectedSize: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

        while true {
            try Task.checkCancellation()
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 {
                return result
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw ScreenshotImageLoadError.unreadable
            }
            guard result.count + bytesRead <= AppConfiguration.maximumInputBytes else {
                throw ScreenshotImageLoadError.fileTooLarge
            }
            result.append(contentsOf: buffer.prefix(bytesRead))
        }
    }

    private static func dimensionsAreWithinLimits(_ source: CGImageSource) -> Bool {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0,
            width <= AppConfiguration.maximumImageDimension,
            height <= AppConfiguration.maximumImageDimension,
            width <= AppConfiguration.maximumPixelCount / height
        else {
            return false
        }
        return true
    }
}
