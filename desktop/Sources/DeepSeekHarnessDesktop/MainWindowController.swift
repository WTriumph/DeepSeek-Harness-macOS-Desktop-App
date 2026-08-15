import AppKit
import HarnessDesktopCore

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let mainViewController = MainViewController()
    var onMainWindowClose: (() -> Void)?
    private var closingForTermination = false
    private var frameObservers: [NSObjectProtocol] = []

    private static let frameDefaultsKey = "MainWindowFrame"

    init() {
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView,
        ]
        let frame = Self.restoredOrDefaultFrame()
        let contentRect = NSWindow.contentRect(forFrameRect: frame, styleMask: styleMask)
        NSLog("desktop: window frame resolved: %@", NSStringFromRect(frame))

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = false
        window.minSize = WindowFramePolicy.minimumSize
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentViewController = mainViewController

        super.init(window: window)

        // The persisted value is a complete NSWindow frame, not a content rect.
        // Apply it after the content controller is installed so later setup cannot
        // replace the restored size with the view controller's preferred size.
        window.setFrame(frame, display: false)
        window.delegate = self
        installFrameObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        frameObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func prepareForTermination() {
        closingForTermination = true
    }

    func windowWillClose(_ notification: Notification) {
        persistFrameNow()
        guard !closingForTermination else { return }
        onMainWindowClose?()
    }

    func persistFrameNow() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        guard WindowFramePolicy.isValidPersistedFrame(frame) else { return }

        NSLog("desktop: window frame persist: %@", NSStringFromRect(frame))
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
    }

    private func installFrameObservers() {
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.persistFrameNow()
            }
            frameObservers.append(token)
        }
    }

    private static func restoredOrDefaultFrame() -> NSRect {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let preferredVisibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame

        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let savedFrame = NSRectFromString(saved)
            if let restored = WindowFramePolicy.restoredFrame(
                savedFrame,
                visibleFrames: visibleFrames,
                preferredVisibleFrame: preferredVisibleFrame
            ) {
                if !NSEqualRects(savedFrame, restored) {
                    NSLog(
                        "desktop: saved window frame constrained: %@ -> %@",
                        NSStringFromRect(savedFrame),
                        NSStringFromRect(restored)
                    )
                }
                return restored
            }
            NSLog("desktop: saved window frame rejected: %@", NSStringFromRect(savedFrame))
        }

        guard let preferredVisibleFrame else {
            return WindowFramePolicy.fallbackFrame
        }
        return WindowFramePolicy.defaultFrame(in: preferredVisibleFrame)
    }
}
