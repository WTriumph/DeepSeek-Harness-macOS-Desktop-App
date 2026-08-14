import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let mainViewController = MainViewController()
    var onMainWindowClose: (() -> Void)?
    private var closingForTermination = false
    private var frameObservers: [NSObjectProtocol] = []

    private static let frameDefaultsKey = "MainWindowFrame"
    private static let minimumWindowWidth: CGFloat = 760
    private static let minimumWindowHeight: CGFloat = 560
    private static let defaultWidthFraction: CGFloat = 0.86
    private static let defaultHeightFraction: CGFloat = 0.9
    private static let maximumDefaultWidth: CGFloat = 1728
    private static let maximumDefaultHeight: CGFloat = 1117

    init() {
        let window = NSWindow(
            contentRect: Self.restoredOrDefaultFrame(),
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
        persistFrame()
        guard !closingForTermination else { return }
        onMainWindowClose?()
    }

    private func installFrameObservers() {
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.persistFrame()
            }
            frameObservers.append(token)
        }
    }

    private func persistFrame() {
        guard let window else { return }
        let frame = window.frame
        guard frame.width >= Self.minimumWindowWidth, frame.height >= Self.minimumWindowHeight else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
        // The app quits immediately after the window closes; flush the write so
        // the restored size survives the termination path.
        UserDefaults.standard.synchronize()
    }

    private static func restoredOrDefaultFrame() -> NSRect {
        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let frame = NSRectFromString(saved)
            if frame.width >= minimumWindowWidth,
               frame.height >= minimumWindowHeight,
               isVisibleOnScreen(frame) {
                return frame
            }
        }
        return defaultFrame()
    }

    private static func defaultFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 1280, height: 820)
        }
        let visible = screen.visibleFrame
        let width = max(minimumWindowWidth, min(visible.width * defaultWidthFraction, maximumDefaultWidth))
        let height = max(minimumWindowHeight, min(visible.height * defaultHeightFraction, maximumDefaultHeight))
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
