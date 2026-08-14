# Changelog

本项目为 DeepSeek Harness 的 macOS 桌面打包，版本号跟随上游 Harness 版本（`0.1.0-rc.5`），桌面构建号记录在 `config/build-versions.env` 的 `DESKTOP_BUILD`。

## [0.1.0-rc.5] Desktop Build 2

### 新增

- 菜单栏「设置…」现在打开 Harness Web UI 的设置面板（Harness 补丁 0006：`dsh:open-settings` 窗口事件）；桌面维护功能移到「数据与维护…」菜单项
- 窗口大小与位置记忆（不再依赖不可靠的系统 frame autosave），首次启动窗口改为屏幕的 86%×90%
- 应用固定中文界面（启动时写入 `AppleLanguages`，WKWebView 与 Harness Web UI 跟随）
- 前端全面汉化（Harness 补丁 0005）：轨迹表/时间线、启动页、聊天状态、工具卡片、设置项等 100+ 处文案与 zh 词典补全
- 构建脚本：`DESKTOP_BUILD` 自动注入 Info.plist；`DEVELOPER_DIR` 未设置时回退 `xcode-select -p`；测试固定 `NODE_ENV=test`
- 开源准备：MIT 许可证、双语 README、CONTRIBUTING、GitHub 议题/PR 模板与 arm64 CI 工作流

### 修复

- 修复测试在 `NODE_ENV=production` 泄漏环境下大面积失败的问题（React `act()` 不支持生产构建）
- 版权说明合法合规：桌面打包版权主体改为 "DeepSeek Harness Desktop contributors"，上游 Harness 版权在 NOTICES 中单独如实标注

## [0.1.0-rc.5] Desktop Build 1

- 初始版本：原生 macOS 桌面壳（AppKit + WKWebView）、内嵌 Node.js 24.18.0 运行时、仅生产依赖部署、首启迁移（`~/.dsh` 导入）、一键卸载与数据备份、运行时冒烟测试
