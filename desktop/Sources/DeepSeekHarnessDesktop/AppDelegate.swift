import AppKit
import HarnessDesktopCore
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let obsoleteMigrationDecisionKey = "LegacyMigrationDecisionV1"

    private let locations = AppDataLocations()
    private lazy var logger = LogFile(fileURL: locations.desktopLog)
    private let migrationService = MigrationService()
    // 懒加载：窗口控制器必须等到 App 完成启动（NSScreen 可用）后再构造，
    // 否则保存的窗口尺寸无法通过屏幕可见性校验，每次启动都会退回兜底尺寸。
    private lazy var mainWindowController = MainWindowController()
    private var processController: HarnessProcessController?
    private var uninstallInProgress = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 桌面版固定使用中文界面：WKWebView 的 navigator.language 跟随应用的
        // AppleLanguages，Harness Web UI 依此选择界面语言。必须在创建任何
        // WebKit 实例之前写入。
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        UserDefaults.standard.removeObject(forKey: Self.obsoleteMigrationDecisionKey)
        AppMenuBuilder.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard activateExistingInstanceIfNeeded() == false else { return }

        do {
            try locations.ensureRuntimeDirectories()
        } catch {
            showFatalError("无法创建应用数据目录。", error: error)
            return
        }

        configureMainWindowActions()
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.append("desktop: application launched")
        handleFirstLaunchMigration()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindowController.prepareForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.append("desktop: applicationWillTerminate")
        // ⌘Q 退出路径可能不触发 windowWillClose，这里兜底保存最终窗口尺寸。
        mainWindowController.persistFrameNow()
        processController?.stopAndWait(timeout: 6)
        logger.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindowController.showWindow(nil)
        }
        mainWindowController.window?.makeKeyAndOrderFront(nil)
        return true
    }

    @objc func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0.1.0-rc.5"
        let desktopBuild = info?["CFBundleVersion"] as? String ?? "3"
        let credits = """
        社区维护的 macOS 桌面发行版，并非 DeepSeek 官方产品，也不代表 DeepSeek 的认可或背书。

        Community-maintained macOS distribution. This is not an official DeepSeek product and is not affiliated with or endorsed by DeepSeek.

        上游 / Upstream: DeepSeek Harness \(shortVersion) - Copyright (c) 2026 DeepSeek - MIT License
        桌面版 / Desktop: Copyright (c) 2026 WTriumph - MIT License
        """
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DeepSeek Harness",
            .applicationVersion: "\(shortVersion) (Desktop \(desktopBuild) / 桌面版 \(desktopBuild))",
            .version: "Harness \(shortVersion) - Desktop Build \(desktopBuild)",
            .credits: NSAttributedString(string: credits),
        ])
    }

    @objc func openHarnessSettings(_ sender: Any?) {
        let view = mainWindowController.mainViewController
        guard view.isHarnessLoaded else {
            showErrorAlert("Harness 尚未就绪", detail: "请等待 Harness 启动完成后再打开设置。")
            return
        }
        view.openHarnessSettings()
    }

    @objc func uninstallApplication(_ sender: Any?) {
        beginUninstall()
    }

    @objc func reloadHarness(_ sender: Any?) {
        mainWindowController.mainViewController.reloadHarness()
    }

    @objc func openDocumentation(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/WTriumph/DeepSeek-Harness-macOS-Desktop-App") else { return }
        NSWorkspace.shared.open(url)
    }

    private func configureMainWindowActions() {
        let view = mainWindowController.mainViewController
        view.onRetry = { [weak self] in self?.restartHarness() }
        view.onOpenLogs = { [weak self] in self?.openLogs() }
        view.onOpenData = { [weak self] in self?.revealDataDirectory() }
        view.onQuit = { NSApp.terminate(nil) }
        mainWindowController.onMainWindowClose = { NSApp.terminate(nil) }
    }

    private func handleFirstLaunchMigration() {
        guard migrationService.shouldOfferMigration(locations: locations) else {
            startHarness()
            return
        }

        let sourceSummary = try? migrationService.inspectLegacyHome(locations: locations)

        let alert = NSAlert()
        alert.messageText = "发现命令行版 DeepSeek Harness 数据"
        alert.informativeText = migrationPromptText(summary: sourceSummary)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "导入副本")
        alert.addButton(withTitle: "全新开始")
        alert.addButton(withTitle: "取消并退出")
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            mainWindowController.mainViewController.showStarting("正在校验并导入 ~/.dsh…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    let summary = try self.migrationService.importLegacyHome(locations: self.locations)
                    self.logger.append("desktop: legacy ~/.dsh imported")
                    DispatchQueue.main.async {
                        self.showMigrationCompleted(summary: summary)
                        self.startHarness()
                    }
                } catch {
                    self.logger.append("desktop: legacy migration failed: \(error)")
                    DispatchQueue.main.async {
                        self.showErrorAlert("导入失败", detail: error.localizedDescription)
                        self.mainWindowController.mainViewController.showError(error.localizedDescription)
                    }
                }
            }
        case .alertSecondButtonReturn:
            startHarness()
        default:
            NSApp.terminate(nil)
        }
    }

    private func migrationPromptText(summary: MigrationSummary?) -> String {
        let base = "可以将 ~/.dsh 的会话、设置、凭据和插件复制到桌面版专属目录。原目录不会被修改或删除。"
        guard let summary else { return base }

        let statistics = "检测到 \(summary.fileCount) 个文件、\(summary.directoryCount) 个目录和 \(summary.symbolicLinkCount) 个符号链接。"
        if summary.containsUserData {
            return "\(base)\n\n\(statistics)"
        }
        return "\(base)\n\n\(statistics) 当前 ~/.dsh 只有匿名标识等元数据，没有可导入的会话、设置或凭据；导入后界面可能不会发生可见变化。"
    }

    private func showMigrationCompleted(summary: MigrationSummary) {
        let size = ByteCountFormatter.string(fromByteCount: summary.totalFileSize, countStyle: .file)
        let statistics = "已复制 \(summary.fileCount) 个文件、\(summary.directoryCount) 个目录和 \(summary.symbolicLinkCount) 个符号链接（\(size)）。"
        let alert = NSAlert()
        alert.messageText = "导入完成 / Import Complete"
        alert.informativeText = summary.containsUserData
            ? "\(statistics) 原始 ~/.dsh 保持不变。\nImport completed. The original ~/.dsh was not modified."
            : "\(statistics) 源目录没有会话、设置或凭据，因此 Harness 界面不会出现可见的数据变化。原始 ~/.dsh 保持不变。\nThe source contained no sessions, settings, or credentials, so no visible Harness data change is expected. The original ~/.dsh was not modified."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "继续 / Continue")
        alert.runModal()
    }

    private func startHarness() {
        do {
            try locations.ensureRuntimeDirectories()
            let configuration = try runtimeConfiguration()
            let controller = HarnessProcessController(configuration: configuration, logger: logger)
            controller.onStateChange = { [weak self, weak controller] state in
                guard let self, self.processController === controller else { return }
                switch state {
                case .starting:
                    self.mainWindowController.mainViewController.showStarting()
                case .ready(let url):
                    self.mainWindowController.mainViewController.loadHarness(at: url)
                case .failed(let message):
                    self.mainWindowController.mainViewController.showError(message)
                case .idle, .stopping, .stopped:
                    break
                }
            }
            processController = controller
            try controller.start()
        } catch {
            logger.append("desktop: Harness start failed: \(error)")
            mainWindowController.mainViewController.showError(error.localizedDescription)
        }
    }

    private func restartHarness() {
        processController?.stopAndWait(timeout: 6)
        processController = nil
        startHarness()
    }

    private func runtimeConfiguration() throws -> HarnessRuntimeConfiguration {
        let runtimeRoot: URL
        if let override = ProcessInfo.processInfo.environment["DSH_RUNTIME_ROOT"], !override.isEmpty {
            runtimeRoot = URL(fileURLWithPath: override, isDirectory: true)
        } else if let resources = Bundle.main.resourceURL {
            runtimeRoot = resources.appendingPathComponent("runtime", isDirectory: true)
        } else {
            throw DesktopAppError.resourcesUnavailable
        }

        let node = runtimeRoot.appendingPathComponent("node", isDirectory: false)
        let dsh = runtimeRoot
            .appendingPathComponent("dsh", isDirectory: true)
            .appendingPathComponent("lib/bin.js", isDirectory: false)
        let environment = EnvironmentBuilder.harnessEnvironment(
            locations: locations,
            embeddedNodeDirectory: node.deletingLastPathComponent()
        )
        return HarnessRuntimeConfiguration(
            nodeExecutable: node,
            dshEntryPoint: dsh,
            workingDirectory: locations.bootstrapWorkspace,
            environment: environment
        )
    }

    private func openLogs() {
        do {
            try FileManager.default.createDirectory(at: locations.logs, withIntermediateDirectories: true)
            NSWorkspace.shared.open(locations.logs)
        } catch {
            showErrorAlert("无法打开日志目录", detail: error.localizedDescription)
        }
    }

    private func revealDataDirectory() {
        do {
            try FileManager.default.createDirectory(at: locations.applicationSupport, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([locations.harnessHome])
        } catch {
            showErrorAlert("无法打开数据目录", detail: error.localizedDescription)
        }
    }

    private func beginUninstall() {
        guard !uninstallInProgress else { return }
        let appBundle = Bundle.main.bundleURL.standardizedFileURL
        guard appBundle.pathExtension.lowercased() == "app" else {
            showErrorAlert("当前不是已打包的 App", detail: "请从 dist/DeepSeek Harness.app 运行卸载。")
            return
        }

        guard let mode = chooseUninstallMode() else { return }
        let workspacePaths: [URL]
        do {
            workspacePaths = mode == .complete ? try WorkspaceDiscovery.discover(locations: locations) : []
        } catch {
            showErrorAlert("无法读取工作区 / Cannot Read Workspaces", detail: error.localizedDescription)
            return
        }

        let plan = UninstallPlan(locations: locations, mode: mode, workspacePaths: workspacePaths)
        let paths: [URL]
        do {
            paths = try plan.removalPaths()
        } catch {
            showErrorAlert("无法生成安全卸载计划 / Unsafe Uninstall Plan", detail: error.localizedDescription)
            return
        }

        guard let shouldBackup = confirmUninstall(
            mode: mode,
            appBundle: appBundle,
            removalPaths: paths,
            workspacePaths: workspacePaths
        ) else {
            return
        }

        var backupDestination: URL?
        if shouldBackup {
            let panel = NSSavePanel()
            panel.title = "保存卸载备份 / Save Uninstall Backup"
            panel.nameFieldStringValue = mode == .complete
                ? "DeepSeek-Harness-Complete-Backup.zip"
                : "DeepSeek-Harness-Desktop-Backup.zip"
            panel.allowedContentTypes = [.zip]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            backupDestination = selected
        }

        uninstallInProgress = true
        processController?.stopAndWait(timeout: 6)
        processController = nil

        if let backupDestination {
            do {
                try BackupService.createBackup(
                    items: backupItems(mode: mode, workspacePaths: workspacePaths),
                    destination: backupDestination,
                    removalPaths: paths
                )
            } catch {
                uninstallInProgress = false
                showErrorAlert("备份失败，尚未卸载 / Backup Failed; Nothing Removed", detail: error.localizedDescription)
                startHarness()
                return
            }
        }

        let launchHelper: () -> Void = { [weak self] in
            guard let self else { return }
            self.launchUninstallHelperAndQuit(
                appBundle: appBundle,
                mode: mode,
                workspacePaths: workspacePaths
            )
        }
        if mode == .applicationOnly {
            launchHelper()
        } else {
            clearWebsiteData(completion: launchHelper)
        }
    }

    private func chooseUninstallMode() -> UninstallMode? {
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 28), pullsDown: false)
        picker.addItems(withTitles: [
            "仅移除 App（保留全部数据） / App Only",
            "标准卸载（保留共享数据和工作区） / Standard",
            "完全卸载（删除所有相关数据） / Complete",
        ])
        picker.selectItem(at: 1)

        let alert = NSAlert()
        alert.messageText = "选择卸载方式 / Choose Uninstall Mode"
        alert.informativeText = "完全卸载会永久删除 ~/.dsh、~/.agents 和 Harness 记录的用户工作区。\nComplete uninstall permanently deletes ~/.dsh, ~/.agents, and registered user workspaces."
        alert.alertStyle = .warning
        alert.accessoryView = picker
        alert.addButton(withTitle: "继续 / Continue")
        alert.addButton(withTitle: "取消 / Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        return [UninstallMode.applicationOnly, .standard, .complete][picker.indexOfSelectedItem]
    }

    private func confirmUninstall(
        mode: UninstallMode,
        appBundle: URL,
        removalPaths: [URL],
        workspacePaths: [URL]
    ) -> Bool? {
        let backupCheckbox: NSButton? = mode == .applicationOnly ? nil : NSButton(
            checkboxWithTitle: mode == .complete
                ? "先备份所有待删除数据（可能很大且包含凭据） / Back up all data first"
                : "先备份桌面版 Harness 数据 / Back up desktop Harness data first",
            target: nil,
            action: nil
        )
        backupCheckbox?.state = .off

        let confirmationField: NSTextField? = mode == .complete
            ? NSTextField(string: "")
            : nil
        confirmationField?.placeholderString = "输入 DELETE ALL / Type DELETE ALL"

        let pathText: String
        switch mode {
        case .applicationOnly:
            pathText = "移到废纸篓 / Move to Trash:\n\(appBundle.path)\n\n保留全部数据 / Preserve all data."
        case .standard:
            pathText = "移到废纸篓 / Move to Trash:\n\(appBundle.path)\n\n永久删除 / Permanently delete:\n"
                + removalPaths.map(\.path).joined(separator: "\n")
                + "\n\n保留 / Preserve: ~/.dsh, ~/.agents, user workspaces"
        case .complete:
            pathText = "移到废纸篓 / Move to Trash:\n\(appBundle.path)\n\n永久删除且无法恢复 / Permanently delete; cannot be undone:\n"
                + removalPaths.map(\.path).joined(separator: "\n")
                + (workspacePaths.isEmpty ? "\n\n未发现已登记工作区 / No registered workspaces found." : "")
        }

        let accessory = uninstallConfirmationView(
            pathText: pathText,
            backupCheckbox: backupCheckbox,
            confirmationField: confirmationField
        )
        let alert = NSAlert()
        alert.messageText = mode == .complete
            ? "完全卸载 DeepSeek Harness？ / Complete Uninstall?"
            : "卸载 DeepSeek Harness？ / Uninstall DeepSeek Harness?"
        alert.informativeText = mode == .complete
            ? "此操作会永久删除下面列出的用户数据。备份 ZIP 可能包含 API 密钥和凭据，请妥善保管。\nThis permanently deletes the user data listed below. The optional backup may contain API keys and credentials."
            : "请核对以下精确路径。 / Review the exact paths below."
        alert.alertStyle = mode == .complete ? .critical : .warning
        alert.accessoryView = accessory
        let confirmButton = alert.addButton(withTitle: "确认卸载 / Uninstall")
        alert.addButton(withTitle: "取消 / Cancel")
        var confirmationObserver: NSObjectProtocol?
        if let confirmationField {
            confirmButton.isEnabled = false
            confirmationObserver = NotificationCenter.default.addObserver(
                forName: NSControl.textDidChangeNotification,
                object: confirmationField,
                queue: .main
            ) { [weak confirmationField, weak confirmButton] _ in
                confirmButton?.isEnabled = confirmationField?.stringValue == "DELETE ALL"
            }
            alert.window.initialFirstResponder = confirmationField
        }
        defer {
            if let confirmationObserver {
                NotificationCenter.default.removeObserver(confirmationObserver)
            }
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        if mode == .complete, confirmationField?.stringValue != "DELETE ALL" {
            showErrorAlert(
                "未确认完全卸载 / Complete Uninstall Not Confirmed",
                detail: "必须准确输入 DELETE ALL，未删除任何内容。\nType DELETE ALL exactly. Nothing was removed."
            )
            return nil
        }
        return backupCheckbox?.state == .on
    }

    private func uninstallConfirmationView(
        pathText: String,
        backupCheckbox: NSButton?,
        confirmationField: NSTextField?
    ) -> NSView {
        let textView = NSTextView(frame: .zero)
        textView.string = pathText
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 620).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 190).isActive = true

        var views: [NSView] = []
        if let confirmationField {
            let label = NSTextField(labelWithString: "永久删除确认 / Permanent deletion confirmation")
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            views.append(label)
            views.append(confirmationField)
            confirmationField.controlSize = .large
            confirmationField.setAccessibilityLabel("输入 DELETE ALL 以确认完全卸载 / Type DELETE ALL to confirm")
            confirmationField.widthAnchor.constraint(equalToConstant: 620).isActive = true
            confirmationField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        views.append(scrollView)
        if let backupCheckbox { views.append(backupCheckbox) }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let extraHeight: CGFloat = (confirmationField == nil ? 0 : 52) + (backupCheckbox == nil ? 0 : 24)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 190 + extraHeight + 16))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func backupItems(mode: UninstallMode, workspacePaths: [URL]) -> [BackupItem] {
        var items = [BackupItem(source: locations.harnessHome, archivePath: "Desktop/Harness")]
        guard mode == .complete else { return items }

        items.append(BackupItem(source: locations.legacyHarnessHome, archivePath: "Shared/.dsh"))
        items.append(BackupItem(source: locations.sharedAgentsHome, archivePath: "Shared/.agents"))
        for (index, workspace) in workspacePaths.enumerated() {
            let name = workspace.lastPathComponent.replacingOccurrences(of: "/", with: "-")
            items.append(BackupItem(
                source: workspace,
                archivePath: String(format: "Workspaces/%03d-%@", index + 1, name)
            ))
        }
        return items
    }

    private func clearWebsiteData(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: completion
        )
    }

    private func launchUninstallHelperAndQuit(
        appBundle: URL,
        mode: UninstallMode,
        workspacePaths: [URL]
    ) {
        do {
            let helperSource = appBundle
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent("DeepSeekHarnessUninstaller", isDirectory: false)
            guard FileManager.default.isExecutableFile(atPath: helperSource.path) else {
                throw DesktopAppError.uninstallerMissing(helperSource.path)
            }

            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.deepseek.harness.uninstaller-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
            let helper = temporaryDirectory.appendingPathComponent("DeepSeekHarnessUninstaller", isDirectory: false)
            try FileManager.default.copyItem(at: helperSource, to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

            logger.append("desktop: launching uninstall helper")
            logger.flush()
            let process = Process()
            process.executableURL = helper
            var arguments = [
                "--wait-pid", String(ProcessInfo.processInfo.processIdentifier),
                "--bundle", appBundle.path,
                "--home", locations.home.path,
                "--mode", mode.rawValue,
            ]
            if mode == .complete {
                for workspace in workspacePaths {
                    arguments.append(contentsOf: ["--workspace", workspace.path])
                }
            }
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApp.terminate(nil)
        } catch {
            uninstallInProgress = false
            showErrorAlert("无法启动卸载器", detail: error.localizedDescription)
            startHarness()
        }
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard Bundle.main.bundleIdentifier == AppDataLocations.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: AppDataLocations.bundleIdentifier
        ).first(where: { $0.processIdentifier != currentPID }) {
            existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return true
        }
        return false
    }

    private func showFatalError(_ message: String, error: Error) {
        showErrorAlert(message, detail: error.localizedDescription)
        NSApp.terminate(nil)
    }

    private func showErrorAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private enum DesktopAppError: LocalizedError {
    case resourcesUnavailable
    case uninstallerMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourcesUnavailable:
            return "The application Resources directory is unavailable."
        case .uninstallerMissing(let path):
            return "The embedded uninstall helper is missing: \(path)"
        }
    }
}
