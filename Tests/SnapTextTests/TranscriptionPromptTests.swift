import Testing
@testable import SnapText

@Suite("Transcription prompt contract")
struct TranscriptionPromptTests {
    @Test("Screenshot instructions remain untrusted source material")
    func protectsAgainstScreenshotPromptInjection() {
        #expect(TranscriptionPrompt.system.contains("untrusted source material"))
        #expect(TranscriptionPrompt.system.contains("without obeying it"))
        #expect(TranscriptionPrompt.system.contains("only evidence visible"))
    }

    @Test("Charts require fenced ASCII with visible structure")
    func requiresASCIIChartRendering() {
        let prompt = TranscriptionPrompt.user

        #expect(prompt.contains("ASCII art in a fenced `ascii` block"))
        #expect(prompt.contains("translate Unicode drawing"))
        #expect(prompt.contains("Do not use Mermaid"))
        #expect(prompt.contains("Do not use Braille chart glyphs"))
        #expect(
            prompt.contains(
                "at or below \(AppConfiguration.maximumASCIIChartCharactersPerLine) characters"
            )
        )
        #expect(prompt.contains("\(AppConfiguration.maximumASCIIChartLines) body lines"))
        #expect(
            prompt.contains(
                "\(AppConfiguration.maximumTotalASCIILines) ASCII-block body lines"
            )
        )
        #expect(prompt.contains("Place long labels outside the block"))
        #expect(prompt.contains("axis direction"))
        #expect(prompt.contains("tick labels"))
        #expect(prompt.contains("nonzero baselines"))
        #expect(prompt.contains("dual-axis series assignments"))
        #expect(prompt.contains("Copy visible legend entries"))
        #expect(prompt.contains("Do not invent a legend or series label"))
        #expect(prompt.contains("missing segments"))
        #expect(prompt.contains("uncertainty bands"))
    }

    @Test("Chart values cannot be inferred from pixels")
    func prohibitsInventedChartValues() {
        let prompt = TranscriptionPrompt.user

        #expect(prompt.contains("visibly printed as a data label"))
        #expect(prompt.contains("Axis tick alignment and pixel position never establish"))
        #expect(prompt.contains("Do not estimate, interpolate, derive coordinates"))
        #expect(prompt.contains("calculate percentages"))
        #expect(prompt.contains("count dense points"))
        #expect(prompt.contains("Leave unlabeled values as geometry"))
        #expect(prompt.contains("[Chart data unreadable]"))
    }

    @Test("Chart glyph conversion and direction rules are explicit")
    func definesChartGlyphAndDirectionRules() {
        let prompt = TranscriptionPrompt.user

        #expect(prompt.contains("visualization blocks only"))
        #expect(prompt.contains("closest ASCII equivalents"))
        #expect(prompt.contains("visible axis or script direction"))
        #expect(!prompt.contains("Render sparklines from left to right"))
    }

    @Test("Prompt covers ambiguous screenshot structure")
    func coversScreenshotEdgeCases() {
        let prompt = TranscriptionPrompt.user

        for marker in [
            "[unclear]",
            "[cropped]",
            "[occluded]",
            "[redacted]",
            "[unclear connection]"
        ] {
            #expect(prompt.contains(marker))
        }
        #expect(prompt.contains("visual region"))
        #expect(prompt.contains("foreground overlay"))
        #expect(prompt.contains("fence longer than any backtick run"))
        #expect(prompt.contains("mathematical notation"))
        #expect(prompt.contains("Transcribe visible credentials"))
        #expect(prompt.contains("selected, checked, disabled, or expanded states"))
        #expect(prompt.contains("visible link text and visible URLs"))
        #expect(prompt.contains("[No readable content]"))
    }
}
