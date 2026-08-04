import Foundation

enum TranscriptionOutputNormalizationError: Error, Equatable {
    case asciiChartBudgetExceeded
    case unterminatedMarkdownFence
    case unsupportedBrailleGlyph
}

enum TranscriptionOutputNormalizer {
    private static let negatedArrowScalars: Set<UInt32> = [
        0x219A, 0x219B, 0x21AE, 0x21CD, 0x21CE, 0x21CF
    ]

    static func normalizeResponse(_ text: String) throws -> String {
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )
        var startIndex = lines.startIndex
        var endIndex = lines.endIndex

        while startIndex < endIndex, isBlankBoundaryLine(lines[startIndex]) {
            startIndex = lines.index(after: startIndex)
        }
        while startIndex < endIndex {
            let previousIndex = lines.index(before: endIndex)
            guard isBlankBoundaryLine(lines[previousIndex]) else { break }
            endIndex = previousIndex
        }

        guard startIndex < endIndex else { return "" }
        return try normalize(lines[startIndex..<endIndex].joined(separator: "\n"))
    }

    static func normalize(_ text: String) throws -> String {
        var activeFence: MarkdownFence?
        var activeASCIIBlockLineCount = 0
        var totalASCIIBlockLineCount = 0
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )
        let normalizedLines = try lines.map { substring -> String in
            let line = String(substring)
            if let fence = activeFence {
                if fence.isClosingLine(line) {
                    activeFence = nil
                    activeASCIIBlockLineCount = 0
                    return line
                }
                if fence.normalizesDrawingCharacters {
                    let normalizedLine = try normalizeDrawingCharacters(in: line)
                    activeASCIIBlockLineCount += 1
                    totalASCIIBlockLineCount += 1
                    guard
                        normalizedLine.count
                            <= AppConfiguration.maximumASCIIChartCharactersPerLine,
                        activeASCIIBlockLineCount <= AppConfiguration.maximumASCIIChartLines,
                        totalASCIIBlockLineCount <= AppConfiguration.maximumTotalASCIILines
                    else {
                        throw TranscriptionOutputNormalizationError.asciiChartBudgetExceeded
                    }
                    return normalizedLine
                }
                return line
            }

            if let fence = MarkdownFence.openingFence(in: line) {
                activeFence = fence
                activeASCIIBlockLineCount = 0
            }
            return line
        }
        if activeFence != nil {
            throw TranscriptionOutputNormalizationError.unterminatedMarkdownFence
        }
        return normalizedLines.joined(separator: "\n")
    }

    private static func isBlankBoundaryLine(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalizeDrawingCharacters(in line: String) throws -> String {
        var previousScalarWasReplaced = false
        return try line.unicodeScalars.reduce(into: "") { result, scalar in
            guard !(0x2800...0x28FF).contains(scalar.value) else {
                throw TranscriptionOutputNormalizationError.unsupportedBrailleGlyph
            }
            if [0xFE0E, 0xFE0F].contains(scalar.value), previousScalarWasReplaced {
                previousScalarWasReplaced = false
            } else if let replacement = asciiReplacement(for: scalar) {
                result.append(replacement)
                previousScalarWasReplaced = true
            } else {
                result.unicodeScalars.append(scalar)
                previousScalarWasReplaced = false
            }
        }
    }

    private static func asciiReplacement(for scalar: Unicode.Scalar) -> String? {
        let value = scalar.value
        switch value {
        case 0x2010...0x2015, 0x2212:
            return "-"

        case 0x2190, 0x21D0:
            return "<-"
        case 0x2191, 0x21D1:
            return "^"
        case 0x2192, 0x21D2:
            return "->"
        case 0x2193, 0x21D3:
            return "v"
        case 0x2194, 0x21D4:
            return "<->"
        case 0x2195, 0x21D5:
            return "^|v"
        case 0x2196:
            return "<^"
        case 0x2197:
            return "^>"
        case 0x2198:
            return "v>"
        case 0x2199:
            return "<v"

        case 0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509,
            0x254C, 0x254D, 0x2550,
            0x2574, 0x2576, 0x2578, 0x257A, 0x257C, 0x257E:
            return "-"
        case 0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B,
            0x254E, 0x254F, 0x2551,
            0x2575, 0x2577, 0x2579, 0x257B, 0x257D, 0x257F:
            return "|"
        case 0x250C...0x254B, 0x2552...0x2570:
            return "+"
        case 0x2571:
            return "/"
        case 0x2572:
            return "\\"
        case 0x2573:
            return "x"

        case 0x2581:
            return "."
        case 0x2582:
            return ":"
        case 0x2583:
            return "-"
        case 0x2584:
            return "="
        case 0x2585:
            return "+"
        case 0x2586:
            return "*"
        case 0x2580:
            return "="
        case 0x2587, 0x2589:
            return "#"
        case 0x2588:
            return "@"
        case 0x258A:
            return "*"
        case 0x258B:
            return "+"
        case 0x258C, 0x2590:
            return "="
        case 0x258D:
            return "-"
        case 0x258E:
            return ":"
        case 0x258F:
            return "."
        case 0x2591:
            return "."
        case 0x2592:
            return ":"
        case 0x2593...0x259F:
            return "#"

        case 0x2022:
            return "."
        case 0x25C6, 0x2666:
            return "*"
        case 0x25C7:
            return "+"
        case 0x25A0, 0x25AA:
            return "#"
        case 0x25A1:
            return "[]"
        case 0x25AB:
            return "o"
        case 0x25A3:
            return "@"
        case 0x25B2:
            return "^"
        case 0x25B3:
            return "A"
        case 0x25BC:
            return "v"
        case 0x25BD:
            return "V"
        case 0x25C0:
            return "<"
        case 0x25C1:
            return "["
        case 0x25B6:
            return ">"
        case 0x25B7:
            return "]"
        case 0x25CB:
            return "O"
        case 0x25CC:
            return ":"
        case 0x25CD:
            return "0"
        case 0x25CE:
            return "@"
        case 0x25CF:
            return "o"

        default:
            if (0x2190...0x21FF).contains(value)
                || (0x2794...0x27BF).contains(value)
                || (0x27F0...0x27FF).contains(value)
                || (0x2900...0x297F).contains(value)
                || (0x1F800...0x1F8FF).contains(value)
            {
                return directionalArrowReplacement(for: scalar)
            }
            if (0x2B00...0x2BFF).contains(value) {
                let name = scalar.properties.name ?? ""
                return name.contains("ARROW")
                    ? directionalArrowReplacement(for: scalar)
                    : geometricReplacement(for: scalar)
            }
            if [0x2605, 0x2606, 0x26AA, 0x26AB, 0x26AC].contains(value) {
                return geometricReplacement(for: scalar)
            }
            if (0x25A0...0x25FF).contains(value) {
                return geometricReplacement(for: scalar)
            }
            if (0x1FB00...0x1FBFF).contains(value) {
                return "#"
            }
            return nil
        }
    }

    private static func directionalArrowReplacement(for scalar: Unicode.Scalar) -> String {
        let name = scalar.properties.name ?? ""
        if name.contains("ANTICLOCKWISE") || name.contains("COUNTERCLOCKWISE") {
            return "(ccw)"
        }
        if name.contains("CLOCKWISE") {
            return "(cw)"
        }

        let usesArrowGrammar = name.contains("ARROW") || name.contains("HARPOON")
        let directionName: String
        let modifierName: String?
        if usesArrowGrammar, let modifierRange = name.range(of: " WITH ") {
            directionName = String(name[..<modifierRange.lowerBound])
            modifierName = String(name[modifierRange.upperBound...])
        } else {
            directionName = name
            modifierName = nil
        }

        let pointsLeft: Bool
        let pointsRight: Bool
        let pointsUp: Bool
        let pointsDown: Bool
        if usesArrowGrammar {
            pointsLeft = containsAny(
                [
                    "LEFTWARDS", "WEST", "LEFT-POINTING", "LEFT RIGHT",
                    "DOWN LEFT", "UP LEFT", "LEFT DOWN", "LEFT UP",
                    "ARROW LEFT", "DIRECTLY LEFT", "LEFT ARROW"
                ],
                in: directionName
            )
            pointsRight = containsAny(
                [
                    "RIGHTWARDS", "EAST", "RIGHT-POINTING", "LEFT RIGHT",
                    "DOWN RIGHT", "UP RIGHT", "RIGHT DOWN", "RIGHT UP",
                    "ARROW RIGHT", "DIRECTLY RIGHT", "RIGHT ARROW"
                ],
                in: directionName
            )
            pointsUp = containsAny(
                [
                    "UPWARDS", "NORTH", "UP-POINTING", "UP DOWN",
                    "UP LEFT", "UP RIGHT", "LEFT UP", "RIGHT UP",
                    "ARROW UP", "DIRECTLY UP", "UP ARROW"
                ],
                in: directionName
            )
            pointsDown = containsAny(
                [
                    "DOWNWARDS", "SOUTH", "DOWN-POINTING", "UP DOWN",
                    "DOWN LEFT", "DOWN RIGHT", "LEFT DOWN", "RIGHT DOWN",
                    "ARROW DOWN", "DIRECTLY DOWN", "DOWN ARROW"
                ],
                in: directionName
            )
        } else {
            pointsLeft = directionName.contains("LEFT") || directionName.contains("WEST")
            pointsRight = directionName.contains("RIGHT") || directionName.contains("EAST")
            pointsUp = directionName.contains("UP")
                || directionName.contains("NORTH")
                || directionName.contains("UPPER")
                || directionName.contains("TOP")
            pointsDown = directionName.contains("DOWN")
                || directionName.contains("SOUTH")
                || directionName.contains("LOWER")
                || directionName.contains("BOTTOM")
        }

        let replacement: String
        switch (pointsLeft, pointsRight, pointsUp, pointsDown) {
        case (true, true, _, _):
            replacement = "<->"
        case (_, _, true, true):
            replacement = "^|v"
        case (true, false, true, false):
            replacement = "<^"
        case (true, false, false, true):
            replacement = "<v"
        case (false, true, true, false):
            replacement = "^>"
        case (false, true, false, true):
            replacement = "v>"
        case (true, false, false, false):
            replacement = "<-"
        case (false, true, false, false):
            replacement = "->"
        case (false, false, true, false):
            replacement = "^"
        case (false, false, false, true):
            replacement = "v"
        default:
            return "?"
        }

        var pathReplacement = replacement
        if let modifierName,
            modifierName.contains("CORNER") || modifierName.contains("TIP")
        {
            pathReplacement += directionSuffix(in: modifierName)
        }

        guard Self.negatedArrowScalars.contains(scalar.value) else {
            return pathReplacement
        }
        switch pathReplacement {
        case "->":
            return "-/->"
        case "<-":
            return "<-/-"
        case "<->":
            return "<-/->"
        case "^":
            return "^/|"
        case "v":
            return "|/v"
        case "^|v":
            return "^/|/v"
        default:
            return "!\(pathReplacement)"
        }
    }

    private static func directionSuffix(in name: String) -> String {
        if name.contains("LEFTWARDS") || name.contains("WEST") {
            return "<-"
        }
        if name.contains("RIGHTWARDS") || name.contains("EAST") {
            return "->"
        }
        if name.contains("UPWARDS") || name.contains("NORTH") {
            return "^"
        }
        if name.contains("DOWNWARDS") || name.contains("SOUTH") {
            return "v"
        }
        return "?"
    }

    private static func containsAny(_ needles: [String], in value: String) -> Bool {
        needles.contains(where: value.contains)
    }

    private static func geometricReplacement(for scalar: Unicode.Scalar) -> String? {
        let name = scalar.properties.name ?? ""
        let isHollow = name.contains("WHITE")
            || name.contains("HOLLOW")
            || name.contains("OUTLINED")
        if name.contains("CIRCLE") || name.contains("ELLIPSE") {
            return isHollow ? "O" : "o"
        }
        if name.contains("SQUARE") || name.contains("RECTANGLE") {
            return isHollow ? "[]" : "#"
        }
        if name.contains("DIAMOND") || name.contains("LOZENGE") {
            return isHollow ? "+" : "*"
        }
        if name.contains("STAR") {
            return isHollow ? "x" : "@"
        }
        if name.contains("TRIANGLE") {
            return directionalArrowReplacement(for: scalar)
        }
        if name.contains("PENTAGON")
            || name.contains("HEXAGON")
            || name.contains("OCTAGON")
            || name.contains("POLYGON")
        {
            return isHollow ? "O" : "#"
        }
        if name.contains("BULLET") || name.contains("DOT") {
            return isHollow ? ":" : "."
        }
        return nil
    }
}

private struct MarkdownFence {
    let marker: Character
    let length: Int
    let normalizesDrawingCharacters: Bool

    static func openingFence(in line: String) -> MarkdownFence? {
        guard let trimmed = fenceSyntax(in: line) else { return nil }
        guard let marker = trimmed.first, marker == "`" || marker == "~" else {
            return nil
        }
        let markerCount = trimmed.prefix { $0 == marker }.count
        guard markerCount >= 3 else { return nil }

        let info = trimmed
            .dropFirst(markerCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard marker != "`" || !info.contains("`") else { return nil }
        let language = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return MarkdownFence(
            marker: marker,
            length: markerCount,
            normalizesDrawingCharacters: language.map {
                ["ascii", "ascii-art"].contains($0)
            } ?? false
        )
    }

    func isClosingLine(_ line: String) -> Bool {
        guard let trimmed = Self.fenceSyntax(in: line) else { return false }
        let markerCount = trimmed.prefix { $0 == marker }.count
        return markerCount >= length && markerCount == trimmed.count
    }

    private static func fenceSyntax(in line: String) -> String? {
        var remainder = line[...]
        var leadingSpaceCount = 0
        while remainder.first == " " {
            leadingSpaceCount += 1
            guard leadingSpaceCount <= 3 else { return nil }
            remainder = remainder.dropFirst()
        }
        guard remainder.first != "\t" else { return nil }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
