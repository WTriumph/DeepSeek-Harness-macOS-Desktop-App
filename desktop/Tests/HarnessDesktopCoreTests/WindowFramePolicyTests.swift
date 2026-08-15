import Foundation
import HarnessDesktopCore
import Testing

@Suite("Main window frame policy")
struct WindowFramePolicyTests {
    @Test func firstLaunchUsesAboutSeventyPercentOfEachScreenDimension() {
        let visibleFrame = rect(x: 0, y: 38, width: 1512, height: 862)

        let frame = WindowFramePolicy.defaultFrame(in: visibleFrame)

        #expect(abs(frame.minX - 226.8) < 0.001)
        #expect(abs(frame.minY - 149) < 0.001)
        #expect(abs(frame.width - 1058.4) < 0.001)
        #expect(abs(frame.height - 640) < 0.001)
        #expect(abs(frame.width / visibleFrame.width - 0.70) < 0.001)
        #expect(frame.height >= 640)
    }

    @Test func validSavedFrameIsRestoredExactly() {
        let visibleFrame = rect(x: 0, y: 38, width: 1512, height: 862)
        let savedFrame = rect(x: 126, y: 101, width: 1316, height: 761)

        let restored = WindowFramePolicy.restoredFrame(
            savedFrame,
            visibleFrames: [visibleFrame],
            preferredVisibleFrame: visibleFrame
        )

        #expect(restored == savedFrame)
    }

    @Test func savedFrameIsConstrainedAfterDisplayChanges() {
        let visibleFrame = rect(x: 0, y: 38, width: 1512, height: 862)
        let oldExternalDisplayFrame = rect(x: 2100, y: -120, width: 1700, height: 1000)

        let restored = WindowFramePolicy.restoredFrame(
            oldExternalDisplayFrame,
            visibleFrames: [visibleFrame],
            preferredVisibleFrame: visibleFrame
        )

        #expect(restored == visibleFrame)
    }

    @Test func detachedDisplayFallsBackToPreferredScreen() {
        let preferredFrame = rect(x: 0, y: 38, width: 1512, height: 862)
        let secondaryFrame = rect(x: 1512, y: 0, width: 1920, height: 1080)
        let detachedDisplayFrame = rect(x: 5000, y: 100, width: 1200, height: 760)

        let restored = WindowFramePolicy.restoredFrame(
            detachedDisplayFrame,
            visibleFrames: [secondaryFrame, preferredFrame],
            preferredVisibleFrame: preferredFrame
        )

        #expect(restored == rect(x: 312, y: 100, width: 1200, height: 760))
    }

    @Test func undersizedSavedFrameIsRejected() {
        let visibleFrame = rect(x: 0, y: 38, width: 1512, height: 862)

        let restored = WindowFramePolicy.restoredFrame(
            rect(x: 100, y: 100, width: 700, height: 500),
            visibleFrames: [visibleFrame],
            preferredVisibleFrame: visibleFrame
        )

        #expect(restored == nil)
    }

    private func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}
