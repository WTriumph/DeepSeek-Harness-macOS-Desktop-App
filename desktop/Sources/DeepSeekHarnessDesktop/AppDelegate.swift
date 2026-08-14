import AppKit
import HarnessDesktopCore
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let migrationDecisionKey = "LegacyMigrationDecisionV1"

    private let locations = AppDataLocations()
    private lazy var logger = LogFile(fileURL: locations.desktopLog)
    private let migrationService = MigrationService()
    private let mainWindowController = MainWindowController()
    private var settingsWindowController: SettingsWindowController?
    private var processController: HarnessProcessController?
    private var uninstallInProgress = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 桌面版固定使用中文界面：WKWebView 的 navigator.language 跟随应用的
        // AppleLanguages，Harness Web UI 依此选择界面语言。必须在创建任何
        // WebKit 实例之前写入。
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
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
        let desktopBuild = info?["CFBundleVersion"] as? String ?? "1"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DeepSeek Harness",
            .applicationVersion: "\(shortVersion) (Desktop \(desktopBuild))",
            .version: "Desktop Build \(desktopBuild)",
            .credits: NSAttributedString(string: "DeepSeek Harness is distributed under the MIT License."),
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

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(locations: locations)
            controller.onRevealData = { [weak self] in self?.revealDataDirectory() }
            controller.onOpenLogs = { [weak self] in self?.openLogs() }
            controller.onReset = { [weak self] in self?.resetHarnessData() }
            controller.onUninstall = { [weak self] in self?.beginUninstall() }
            settingsWindowController = controller
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func uninstallApplication(_ sender: Any?) {
        beginUninstall()
    }

    @objc func reloadHarness(_ sender: Any?) {
        mainWindowController.mainViewController.reloadHarness()
    }

    @objc func openDocumentation(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/deepseek-ai/deepseek-harness") else { return }
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
        let decision = UserDefaults.standard.string(forKey: Self.migrationDecisionKey)
        guard decision == nil, migrationService.shouldOfferMigration(locations: locations) else {
            startHarness()
            return
        }

        let alert = NSAlert()
        alert.messageText = "发现命令行版 DeepSeek Harness 数据"
        alert.informativeText = "可以将 ~/.dsh 的会话、设置、凭据和插件复制到桌面版专属目录。原目录不会被修改或删除。"
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
                    try self.migrationService.importLegacyHome(locations: self.locations)
                    UserDefaults.standard.set("imported", forKey: Self.migrationDecisionKey)
                    self.logger.append("desktop: legacy ~/.dsh imported")
                    DispatchQueue.main.async { self.startHarness() }
                } catch {
                    self.logger.append("desktop: legacy migration failed: \(error)")
                    DispatchQueue.main.async {
                        self.showErrorAlert("导入失败", detail: error.localizedDescription)
                        self.mainWindowController.mainViewController.showError(error.localizedDescription)
                    }
                }
            }
        case .alertSecondButtonReturn:
            UserDefaults.standard.set("fresh", forKey: Self.migrationDecisionKey)
            startHarness()
        default:
            NSApp.terminate(nil)
        }
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

    private func resetHarnessData() {
        let alert = NSAlert()
        alert.messageText = "重置桌面版 Harness 数据？"
        alert.informativeText = "这会删除桌面版的会话、设置、API 凭据、插件和技能。不会删除 ~/.dsh、~/.agents 或任何工作区。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        processController?.stopAndWait(timeout: 6)
        processController = nil
        clearWebsiteData { [weak self] in
            guard let self else { return }
            do {
                if FileManager.default.fileExists(atPath: self.locations.harnessHome.path) {
                    try FileManager.default.removeItem(at: self.locations.harnessHome)
                }
                try FileManager.default.createDirectory(at: self.locations.harnessHome, withIntermediateDirectories: true)
                self.logger.append("desktop: Harness data reset")
                self.startHarness()
            } catch {
                self.showErrorAlert("重置失败", detail: error.localizedDescription)
                self.startHarness()
            }
        }
    }

    private func beginUninstall() {
        guard !uninstallInProgress else { return }
        let appBundle = Bundle.main.bundleURL.standardizedFileURL
        guard appBundle.pathExtension.lowercased() == "app" else {
            showErrorAlert("当前不是已打包的 App", detail: "请从 dist/DeepSeek Harness.app 运行卸载。")
            return
        }

        let paths: [URL]
        do {
            paths = try UninstallPlan(locations: locations).removalPaths()
        } catch {
            showErrorAlert("无法生成安全卸载计划", detail: error.localizedDescription)
            return
        }

        let backupCheckbox = NSButton(checkboxWithTitle: "卸载前备份 Harness 数据", target: nil, action: nil)
        backupCheckbox.state = .off
        let alert = NSAlert()
        alert.messageText = "卸载 DeepSeek Harness？"
        alert.informativeText = "App 将移到废纸篓，并删除以下桌面版数据：\n\n"
            + paths.map(\.path).joined(separator: "\n")
            + "\n\n明确保留：~/.dsh、~/.agents 和所有工作区。"
        alert.alertStyle = .critical
        alert.accessoryView = backupCheckbox
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var backupDestination: URL?
        if backupCheckbox.state == .on, FileManager.default.fileExists(atPath: locations.harnessHome.path) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "DeepSeek-Harness-Backup.zip"
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
                try BackupService.createHarnessBackup(source: locations.harnessHome, destination: backupDestination)
            } catch {
                uninstallInProgress = false
                showErrorAlert("备份失败，尚未卸载", detail: error.localizedDescription)
                startHarness()
                return
            }
        }

        clearWebsiteData { [weak self] in
            self?.launchUninstallHelperAndQuit(appBundle: appBundle)
        }
    }

    private func clearWebsiteData(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: completion
        )
    }

    private func launchUninstallHelperAndQuit(appBundle: URL) {
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
            process.arguments = [
                "--wait-pid", String(ProcessInfo.processInfo.processIdentifier),
                "--bundle", appBundle.path,
                "--home", locations.home.path,
            ]
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
