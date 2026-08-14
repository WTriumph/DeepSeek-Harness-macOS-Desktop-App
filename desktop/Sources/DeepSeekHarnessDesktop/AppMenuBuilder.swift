import AppKit

enum AppMenuBuilder {
    static func install() {
        let main = NSMenu()
        NSApplication.shared.mainMenu = main

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "DeepSeek Harness")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 DeepSeek Harness", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(AppDelegate.openHarnessSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "数据与维护…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "卸载 DeepSeek Harness…", action: #selector(AppDelegate.uninstallApplication(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "服务")
        appMenu.addItem(services)
        NSApplication.shared.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 DeepSeek Harness", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "显示")
        viewItem.submenu = view
        view.addItem(withTitle: "重新载入", action: #selector(AppDelegate.reloadHarness(_:)), keyEquivalent: "r")
        let fullScreen = view.addItem(withTitle: "进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let window = NSMenu(title: "窗口")
    windowItem.submenu = window
    window.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    window.addItem(.separator())
    window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "前置所有窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApplication.shared.windowsMenu = window

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: "帮助")
        helpItem.submenu = help
        help.addItem(withTitle: "DeepSeek Harness 文档", action: #selector(AppDelegate.openDocumentation(_:)), keyEquivalent: "?")
        NSApplication.shared.helpMenu = help
    }
}
