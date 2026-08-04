import Testing
@testable import Screenie

@Suite("Transcription output normalizer")
struct TranscriptionOutputNormalizerTests {
    @Test("Blank wrapper lines are removed without stripping content indentation")
    func removesOnlyBlankBoundaryLines() throws {
        let input = "\n \t\n  indented text\nline with hard break  \n\t\n"

        #expect(
            try TranscriptionOutputNormalizer.normalizeResponse(input)
                == "  indented text\nline with hard break  "
        )
    }

    @Test("Unicode drawing glyphs become ASCII only inside ASCII fences")
    func normalizesChartGeometryWithoutChangingSurroundingText() throws {
        let input = """
        Visible arrow: →
        ```ascii
        收入
        10 ┤ ███ ● ○ ◆ ◇ ■ □ ▶️
         0 └──→
        ```
        ```text
        semantic −10, A → B, ●
        ```
        ```swift
        let glyph = "└"
        ```
        """
        let expected = """
        Visible arrow: →
        ```ascii
        收入
        10 + @@@ o O * + # [] >
         0 +--->
        ```
        ```text
        semantic −10, A → B, ●
        ```
        ```swift
        let glyph = "└"
        ```
        """

        #expect(try TranscriptionOutputNormalizer.normalize(input) == expected)
    }

    @Test("A longer chart fence can contain a shorter backtick run")
    func respectsFenceLength() throws {
        let input = """
        ````ascii
        ┌─┐
        ```
        └─┘
        ````
        """
        let expected = """
        ````ascii
        +-+
        ```
        +-+
        ````
        """

        #expect(try TranscriptionOutputNormalizer.normalize(input) == expected)
    }

    @Test("ASCII and tilde chart fences are normalized")
    func supportsAlternateChartFenceLabels() throws {
        let input = """
        ~~~ascii-art
        ▁▂▃▄▅▆▇█ ◢ ➜ ⬅ ↔ ↕
        ~~~
        """

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == """
                ~~~ascii-art
                .:-=+*#@ v> -> <- <-> ^|v
                ~~~
                """
        )
    }

    @Test("Common square, circle, and star series marks stay distinct")
    func normalizesCommonSeriesMarks() throws {
        let input = """
        ```ascii
        • ◆ ★ ◇ ☆ ⬛ ⬜ ⬤ ⚫ ⚪
        ```
        """

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == """
                ```ascii
                . * @ + x # [] o o O
                ```
                """
        )
    }

    @Test("Negated arrows keep their blocked-edge meaning")
    func preservesNegatedArrowMeaning() throws {
        let input = """
        ```ascii
        A ↛ B
        C ↮ D
        ```
        """

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == """
                ```ascii
                A -/-> B
                C <-/-> D
                ```
                """
        )
    }

    @Test("Mixed block symbols that are not geometry remain visible labels")
    func preservesNonGeometricSymbolsInMixedBlock() throws {
        let input = """
        ```ascii
        Keys: ⭾ ⮖
        ```
        """

        #expect(try TranscriptionOutputNormalizer.normalize(input) == input)
    }

    @Test("ASCII chart blocks enforce line, width, and response budgets")
    func enforcesASCIIChartBudgets() throws {
        let maximumWidthLine = String(
            repeating: "#",
            count: AppConfiguration.maximumASCIIChartCharactersPerLine
        )
        let maximumHeightBody = Array(
            repeating: "#",
            count: AppConfiguration.maximumASCIIChartLines
        ).joined(separator: "\n")
        let allowedWidth = "```ascii\n\(maximumWidthLine)\n```"
        #expect(try TranscriptionOutputNormalizer.normalize(allowedWidth) == allowedWidth)

        let allowedHeight = "```ascii\n\(maximumHeightBody)\n```"
        #expect(try TranscriptionOutputNormalizer.normalize(allowedHeight) == allowedHeight)

        let tooWide = "```ascii\n\(maximumWidthLine)#\n```"
        #expect(throws: TranscriptionOutputNormalizationError.asciiChartBudgetExceeded) {
            try TranscriptionOutputNormalizer.normalize(tooWide)
        }

        let tooTallBody = Array(
            repeating: "#",
            count: AppConfiguration.maximumASCIIChartLines + 1
        ).joined(separator: "\n")
        #expect(throws: TranscriptionOutputNormalizationError.asciiChartBudgetExceeded) {
            try TranscriptionOutputNormalizer.normalize("```ascii\n\(tooTallBody)\n```")
        }

        let singleLineBlocks = Array(
            repeating: "```ascii\n#\n```",
            count: AppConfiguration.maximumTotalASCIILines + 1
        ).joined(separator: "\n")
        #expect(throws: TranscriptionOutputNormalizationError.asciiChartBudgetExceeded) {
            try TranscriptionOutputNormalizer.normalize(singleLineBlocks)
        }
    }

    @Test("CRLF chart fences are normalized and block glyphs stay inside the fence")
    func normalizesCRLFChartFence() throws {
        let input = "```ascii\r\n10 ┤ ▀█\r\n```\r\n"

        #expect(
            try TranscriptionOutputNormalizer.normalizeResponse(input)
                == "```ascii\n10 + =@\n```"
        )
    }

    @Test("Diagonal arrows preserve all four directions")
    func preservesDiagonalArrowDirections() throws {
        let input = "```ascii\n↖ ↗ ↘ ↙\n```"

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == "```ascii\n<^ ^> v> <v\n```"
        )
    }

    @Test("Arrow styling words do not override direction or imply negation")
    func ignoresArrowStylingWords() throws {
        let input = "```ascii\n↼ ➪ ➯ ⇞ ⇟\n```"

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == "```ascii\n<- -> -> ^ v\n```"
        )
    }

    @Test("Arrow corner and tip modifiers preserve their path direction")
    func preservesArrowPathModifiers() throws {
        let input = "```ascii\n↴ ↵ ↰ ↳\n```"

        #expect(
            try TranscriptionOutputNormalizer.normalize(input)
                == "```ascii\n->v v<- ^<- v->\n```"
        )
    }

    @Test("An unterminated ASCII fence is rejected")
    func rejectsUnterminatedASCIIFence() {
        #expect(throws: TranscriptionOutputNormalizationError.unterminatedMarkdownFence) {
            try TranscriptionOutputNormalizer.normalizeResponse(
                "```ascii\n10 ┤ ███"
            )
        }
    }

    @Test("Braille chart glyphs are rejected instead of collapsed")
    func rejectsBrailleChartGlyph() {
        #expect(throws: TranscriptionOutputNormalizationError.unsupportedBrailleGlyph) {
            try TranscriptionOutputNormalizer.normalizeResponse(
                "```ascii\n⠋⠙⠹\n```"
            )
        }
    }

    @Test("A literal ASCII fence nested in a larger Markdown fence is unchanged")
    func preservesNestedLiteralASCIIFence() throws {
        let input = """
        ````markdown
        ```ascii
        ┌─┐
        ```
        ````
        """

        #expect(try TranscriptionOutputNormalizer.normalizeResponse(input) == input)
    }

    @Test("A four-space-indented literal fence is not treated as a chart fence")
    func preservesIndentedLiteralFence() throws {
        let input = """
            ```ascii
            ┌─┐
            ```
        """

        #expect(try TranscriptionOutputNormalizer.normalizeResponse(input) == input)
    }

    @Test("A backtick in a backtick-fence info string leaves it literal")
    func rejectsInvalidBacktickFenceInfo() throws {
        let input = """
        ````ascii `literal`
        ```ascii
        ┌─┐
        ```
        """
        let expected = """
        ````ascii `literal`
        ```ascii
        +-+
        ```
        """

        #expect(try TranscriptionOutputNormalizer.normalizeResponse(input) == expected)
    }

    @Test("Invisible wrapper lines are removed but embedded zero-width text is preserved")
    func handlesZeroWidthBoundaryLines() throws {
        let zeroWidthSpace = "\u{200B}"
        let input = "\(zeroWidthSpace)\nleft\(zeroWidthSpace)right\n\(zeroWidthSpace)"

        #expect(
            try TranscriptionOutputNormalizer.normalizeResponse(input)
                == "left\(zeroWidthSpace)right"
        )
    }
}
