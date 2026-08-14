import AppKit
import HarnessDesktopCore

final class SettingsWindowController: NSWindowController {
    var onRevealData: (() -> Void)?
    var onOpenLogs: (() -> Void)?
    var onReset: (() -> Void)?
    var onUninstall: (() -> Void)?

    init(locations: AppDataLocations) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness 数据与维护"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = makeViewController(locations: locations)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeViewController(locations: AppDataLocations) -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root

        let title = NSTextField(labelWithString: "DeepSeek Harness")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let version = NSTextField(labelWithString: "Harness 0.1.0-rc.5 · Desktop 1")
        version.textColor = .secondaryLabelColor

        let dataTitle = NSTextField(labelWithString: "应用数据")
        dataTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let dataPath = NSTextField(wrappingLabelWithString: locations.harnessHome.path)
        dataPath.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dataPath.textColor = .secondaryLabelColor

        let revealData = NSButton(title: "在 Finder 中显示", target: self, action: #selector(revealDataAction))
        let openLogs = NSButton(title: "打开日志", target: self, action: #selector(openLogsAction))
        let dataButtons = NSStackView(views: [revealData, openLogs])
        dataButtons.orientation = .horizontal
        dataButtons.spacing = 8

        let divider = NSBox()
        divider.boxType = .separator

        let maintenanceTitle = NSTextField(labelWithString: "维护")
        maintenanceTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let maintenanceText = NSTextField(wrappingLabelWithString: "重置会删除桌面版的会话、设置和凭据。卸载还会清除缓存、日志和 WebKit 数据，但不会删除 ~/.dsh、~/.agents 或任何工作区。")
        maintenanceText.textColor = .secondaryLabelColor

        let reset = NSButton(title: "重置 Harness 数据…", target: self, action: #selector(resetAction))
        let uninstall = NSButton(title: "卸载 DeepSeek Harness…", target: self, action: #selector(uninstallAction))
        uninstall.contentTintColor = .systemRed
        let maintenanceButtons = NSStackView(views: [reset, uninstall])
        maintenanceButtons.orientation = .horizontal
        maintenanceButtons.spacing = 8

        let stack = NSStackView(views: [
            title, version,
            spacer(8),
            dataTitle, dataPath, dataButtons,
            spacer(8), divider, spacer(8),
            maintenanceTitle, maintenanceText, maintenanceButtons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dataPath.widthAnchor.constraint(equalTo: stack.widthAnchor),
            maintenanceText.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return controller
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    @objc private func revealDataAction() { onRevealData?() }
    @objc private func openLogsAction() { onOpenLogs?() }
    @objc private func resetAction() { onReset?() }
    @objc private func uninstallAction() { onUninstall?() }
}
