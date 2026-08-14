import AppKit
import HarnessDesktopCore
import WebKit

final class MainViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var onRetry: (() -> Void)?
    var onOpenLogs: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onQuit: (() -> Void)?

    private let webView: WKWebView
    private let statusView = NSView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "DeepSeek Harness")
    private let detailLabel = NSTextField(wrappingLabelWithString: "正在启动…")
    private let buttons = NSStackView()
    private var allowedOrigin: URLComponents?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        statusView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)
        root.addSubview(statusView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: root.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        configureStatusView()
        self.view = root
    }

    func showStarting(_ detail: String = "正在启动本地 Harness…") {
        allowedOrigin = nil
        webView.isHidden = true
        statusView.isHidden = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        detailLabel.stringValue = detail
        setButtons([])
    }

    func showError(_ message: String) {
        webView.isHidden = true
        statusView.isHidden = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        detailLabel.stringValue = message
        setButtons([
            actionButton("重试", action: #selector(retry)),
            actionButton("打开日志", action: #selector(openLogs)),
            actionButton("显示数据目录", action: #selector(openData)),
            actionButton("退出", action: #selector(quit)),
        ])
    }

    func loadHarness(at url: URL) {
        allowedOrigin = URLComponents(url: url, resolvingAgainstBaseURL: false)
        statusView.isHidden = true
        webView.isHidden = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// Whether the Harness page is loaded and interactive (the status view is hidden).
    var isHarnessLoaded: Bool {
        webView.isHidden == false
    }

    /// Opens the Harness Web UI settings panel. The Harness client listens for
    /// `dsh:open-settings` on window (desktop patch 0006); the native menu bar
    /// routes its 设置… item here.
    func openHarnessSettings() {
        guard isHarnessLoaded else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new Event('dsh:open-settings'))",
            completionHandler: nil
        )
    }

    func reloadHarness() {
        guard !webView.isHidden else { return }
        webView.reload()
    }

    private func configureStatusView() {
        statusView.wantsLayer = true
        statusView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 8
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, spinner, detailLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: statusView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: statusView.widthAnchor, multiplier: 0.72),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
        ])
        showStarting()
    }

    private func setButtons(_ newButtons: [NSView]) {
        buttons.arrangedSubviews.forEach { view in
            buttons.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        newButtons.forEach(buttons.addArrangedSubview)
        buttons.isHidden = newButtons.isEmpty
    }

    private func actionButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func retry() { onRetry?() }
    @objc private func openLogs() { onOpenLogs?() }
    @objc private func openData() { onOpenData?() }
    @objc private func quit() { onQuit?() }

    private func isAllowedHarnessURL(_ url: URL) -> Bool {
        guard let allowedOrigin,
              let candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }
        return candidate.scheme == allowedOrigin.scheme
            && candidate.host == "127.0.0.1"
            && candidate.port == allowedOrigin.port
            && candidate.user == nil
            && candidate.password == nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if url.scheme == "about" || isAllowedHarnessURL(url) {
            decisionHandler(.allow)
            return
        }
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isAllowedHarnessURL(url) {
                webView.load(navigationAction.request)
            } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "DeepSeek Harness"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: view.window!) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "DeepSeek Harness"
        alert.informativeText = message
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: view.window!) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: view.window!) { result in
            completionHandler(result == .OK ? panel.url : nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {}

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let window = view.window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
}
