import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let mainViewController = MainViewController()
    var onMainWindowClose: (() -> Void)?
    private var closingForTermination = false
    private var frameObservers: [NSObjectProtocol] = []

    private static let frameDefaultsKey = "MainWindowFrame"
    private static let minimumWindowWidth: CGFloat = 760
    private static let minimumWindowHeight: CGFloat = 560
    // 首次启动默认尺寸：接近铺满可用屏幕，仅留少量边距。
    private static let defaultFrameInset: CGFloat = 40
    private static let fallbackWidth: CGFloat = 1280
    private static let fallbackHeight: CGFloat = 820

    init() {
        let frame = Self.restoredOrDefaultFrame()
        NSLog("desktop: window frame resolved: %@", NSStringFromRect(frame))
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: Self.minimumWindowWidth, height: Self.minimumWindowHeight)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentViewController = mainViewController
        super.init(window: window)
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

    /// Persists the current window frame immediately. Also called from
    /// `applicationWillTerminate` so ⌘Q exits keep the final size even if the
    /// close path skips `windowWillClose`.
    func persistFrameNow() {
        guard let window else { return }
        let frame = window.frame
        guard frame.width >= Self.minimumWindowWidth, frame.height >= Self.minimumWindowHeight else { return }
        NSLog("desktop: window frame persist: %@", NSStringFromRect(frame))
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
        // The app quits immediately after the window closes; flush the write so
        // the restored size survives the termination path.
        UserDefaults.standard.synchronize()
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
        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let frame = NSRectFromString(saved)
            if frame.width >= minimumWindowWidth,
               frame.height >= minimumWindowHeight,
               isVisibleOnScreen(frame) {
                return frame
            }
            NSLog("desktop: saved window frame rejected: %@", NSStringFromRect(frame))
        }
        return defaultFrame()
    }

    private static func defaultFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            // Screens can be empty when the controller is constructed before
            // the app finishes launching; the caller re-resolves the frame
            // once screens are available (see AppDelegate).
            return NSRect(x: 0, y: 0, width: fallbackWidth, height: fallbackHeight)
        }
        let visible = screen.visibleFrame
        let width = max(minimumWindowWidth, min(visible.width - defaultFrameInset * 2, visible.width))
        let height = max(minimumWindowHeight, min(visible.height - defaultFrameInset * 2, visible.height))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func isVisibleOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 200 && overlap.height >= 100
        }
    }
}
