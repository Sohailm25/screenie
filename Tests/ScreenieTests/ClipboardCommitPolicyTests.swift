import Testing
@testable import Screenie

@Suite("Clipboard commit policy")
struct ClipboardCommitPolicyTests {
    @Test("Unchanged clipboard permits the write")
    func allowsWriteWhenClipboardDidNotChange() {
        #expect(
            ClipboardCommitPolicy.shouldWrite(
                startingChangeCount: 41,
                currentChangeCount: 41
            )
        )
    }

    @Test("User clipboard change blocks the write")
    func rejectsWriteWhenClipboardChangedDuringInference() {
        #expect(
            !ClipboardCommitPolicy.shouldWrite(
                startingChangeCount: 41,
                currentChangeCount: 42
            )
        )
    }

    @Test("Any unequal change counts block the write")
    func rejectsWriteForAnyDifferentChangeCount() {
        #expect(
            !ClipboardCommitPolicy.shouldWrite(
                startingChangeCount: Int.max,
                currentChangeCount: 0
            )
        )
    }
}
