import CoreGraphics
import Foundation

public enum WindowFramePolicy {
    public static let minimumSize = CGSize(width: 760, height: 560)
    public static let fallbackFrame = CGRect(
        origin: CGPoint(x: 0, y: 0),
        size: CGSize(width: 1440, height: 900)
    )

    private static let defaultVisibleFraction: CGFloat = 0.70
    private static let minimumDefaultSize = CGSize(width: 1000, height: 640)

    public static func isValidPersistedFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= minimumSize.width
            && frame.height >= minimumSize.height
    }

    public static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
        guard isUsableVisibleFrame(visibleFrame) else { return fallbackFrame }

        let width = min(
            visibleFrame.width,
            max(minimumDefaultSize.width, visibleFrame.width * defaultVisibleFraction)
        )
        let height = min(
            visibleFrame.height,
            max(minimumDefaultSize.height, visibleFrame.height * defaultVisibleFraction)
        )

        return CGRect(
            origin: CGPoint(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2
            ),
            size: CGSize(width: width, height: height)
        )
    }

    public static func restoredFrame(
        _ savedFrame: CGRect,
        visibleFrames: [CGRect],
        preferredVisibleFrame: CGRect?
    ) -> CGRect? {
        guard isValidPersistedFrame(savedFrame) else { return nil }

        let usableFrames = visibleFrames.filter(isUsableVisibleFrame)
        let intersectionCandidate = usableFrames.max { lhs, rhs in
            intersectionArea(of: savedFrame, with: lhs) < intersectionArea(of: savedFrame, with: rhs)
        }
        let intersectingFrame = intersectionCandidate.flatMap {
            intersectionArea(of: savedFrame, with: $0) > 0 ? $0 : nil
        }
        let target = intersectingFrame
            ?? preferredVisibleFrame.flatMap { isUsableVisibleFrame($0) ? $0 : nil }
            ?? usableFrames.first

        guard let target else { return savedFrame }
        return constrained(savedFrame, to: target)
    }

    private static func constrained(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumSize.width), visibleFrame.width)
        let height = min(max(frame.height, minimumSize.height), visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    private static func intersectionArea(of lhs: CGRect, with rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func isUsableVisibleFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
