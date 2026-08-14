# DeepSeek Harness Desktop for macOS

中文 | English

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的 macOS 桌面打包：把 Harness 的 Web UI 装进原生 App，内嵌 Node.js 运行时，开箱即用。

> **社区打包声明**：本项目是社区维护的 macOS 桌面打包，**不是 DeepSeek 官方发布，与 DeepSeek 无隶属或背书关系**。"DeepSeek Harness" 名称仅用于指代本仓库再分发的开源软件（[MIT](https://github.com/deepseek-ai/deepseek-harness/blob/main/LICENSE)）。"DeepSeek" 商标归其权利人所有。

## 特性

- 原生 macOS App（AppKit + WKWebView），启动即打开本地 Harness Web UI（仅监听 `127.0.0.1` 随机端口）
- 内嵌 Node.js 24.18.0 与仅生产依赖的 Harness 运行时，无需自行安装 Node/pnpm
- 全中文界面（含上游 Web UI 的完整汉化补丁）；菜单栏「设置…」直达 Harness 设置面板
- 窗口大小与位置记忆；单实例运行
- 独立数据目录（不影响命令行版 `~/.dsh`），首次启动可从 `~/.dsh` 导入
- 一键卸载（保留 `~/.dsh`、`~/.agents`、工作区与外部链接目标）；可选数据备份

## 系统要求

- macOS 13 或更高版本（含 macOS 15+）
- Apple Silicon（arm64）

## 构建

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  ./scripts/build-app.sh
```

- 不需要显式设置 `DEVELOPER_DIR`：脚本会依次尝试 Xcode-beta 与 `xcode-select -p`，也可用环境变量覆盖。
- 源 ZIP（`deepseek-harness-master.zip`）不可变，构建前后都会校验 SHA-256（见 `config/build-versions.env`）。
- Harness 补丁列于 `patches/harness/series`，每次构建都应用到全新解压的源码上。
- 产物：

```text
dist/DeepSeek Harness.app
dist/DeepSeek-Harness-macos-arm64.zip
```

App 内只包含 Node 可执行文件与生产依赖；npm/pnpm 仅用于构建，不会进入运行时。

## 安装

- 直接拷贝 `DeepSeek Harness.app` 到 `/Applications`。
- 本仓库产物使用 ad-hoc 签名：首次打开如遇 Gatekeeper 提示，右键 App →「打开」，或执行 `xattr -cr "/Applications/DeepSeek Harness.app"`。自行分发时请用你自己的证书签名。

## 数据与卸载

Harness 数据目录：

```text
~/Library/Application Support/DeepSeek Harness/Harness
```

- 卸载：App 菜单「DeepSeek Harness > 卸载 DeepSeek Harness…」（支持先备份数据）。
- 命令行恢复脚本（可用 `--dry-run` 预览动作）：

```sh
./scripts/uninstall-deepseek-harness.sh --dry-run
```

两条卸载路径都保留 `~/.dsh`、`~/.agents`、用户工作区和外部符号链接目标。

## 目录结构

```text
config/      版本与校验和（构建不可变输入）
patches/     对上游 Harness 源码的补丁（series 声明应用顺序）
desktop/     Swift 桌面壳（SPM：主 App、卸载助手、共享核心库）
scripts/     构建 / 运行时冒烟测试 / 卸载脚本
deepseek-harness-master.zip  上游 0.1.0-rc.5 不可变源码
dist/        构建产物（不提交到仓库）
```

## 上游致谢

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 0.1.0-rc.5，MIT License，© 2026 DeepSeek。
- Node.js 24.18.0（随 App 分发）；其余第三方组件与许可见 `desktop/Resources/THIRD-PARTY-NOTICES.txt`。

## 发布到 GitHub

1. 在 GitHub 创建公开仓库（不勾选自动初始化文件）。
2. 本地添加远端并推送：

```sh
git remote add origin https://github.com/<你>/<仓库名>.git
git branch -M main
git push -u origin main
```

3. 发布版本：把 `dist/DeepSeek-Harness-macos-arm64.zip` 上传为 Release 附件（CI 的 build 工作流也会产出同款 artifact）。

## 许可证

[MIT](LICENSE) © 2026 DeepSeek Harness Desktop contributors

---

# DeepSeek Harness Desktop for macOS

[中文](#deepseek-harness-desktop-for-macos) | English

A macOS desktop packaging of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`): the Harness Web UI in a native app with an embedded Node.js runtime — no setup required.

> **Community packaging notice**: this is a community-maintained macOS packaging, **not an official DeepSeek release, and it is not affiliated with or endorsed by DeepSeek**. The "DeepSeek Harness" name refers only to the open-source software ([MIT](https://github.com/deepseek-ai/deepseek-harness/blob/main/LICENSE)) redistributed here. The "DeepSeek" trademark belongs to its owner.

## Features

- Native macOS app (AppKit + WKWebView) that boots the local Harness Web UI on a random `127.0.0.1` port
- Embedded Node.js 24.18.0 plus a production-only Harness runtime — no Node/pnpm install required
- Fully localized Chinese UI (including upstream Web UI translation patches); the menu bar 设置… opens the Harness settings panel directly
- Window size/position persistence; single-instance
- Isolated data directory (does not touch the CLI's `~/.dsh`); first-run import from `~/.dsh`
- One-click uninstall (preserves `~/.dsh`, `~/.agents`, workspaces, and external symlink targets); optional data backup

## Requirements

- macOS 13 or newer (including macOS 15+)
- Apple Silicon (arm64)

## Building

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  ./scripts/build-app.sh
```

- `DEVELOPER_DIR` is optional: the script falls back from Xcode-beta to `xcode-select -p`, and the environment variable always wins.
- The source ZIP (`deepseek-harness-master.zip`) is immutable and SHA-256 verified before and after every build (see `config/build-versions.env`).
- Harness patches are listed in `patches/harness/series` and applied to a fresh extraction on every build.
- Outputs:

```text
dist/DeepSeek Harness.app
dist/DeepSeek-Harness-macos-arm64.zip
```

The final app contains only the Node executable and production dependencies; npm/pnpm are build-time tools and never ship in the runtime.

## Installing

- Copy `DeepSeek Harness.app` into `/Applications`.
- The shipped artifact is ad-hoc signed: on the first Gatekeeper prompt, right-click the app → Open, or run `xattr -cr "/Applications/DeepSeek Harness.app"`. Sign with your own certificate when distributing.

## Data and uninstall

Harness data lives at:

```text
~/Library/Application Support/DeepSeek Harness/Harness
```

- Uninstall via the app menu **DeepSeek Harness > Uninstall DeepSeek Harness…** (optional backup first).
- Recovery script (preview with `--dry-run`):

```sh
./scripts/uninstall-deepseek-harness.sh --dry-run
```

Both paths preserve `~/.dsh`, `~/.agents`, user workspaces, and external symlink targets.

## Layout

```text
config/      versions and checksums (immutable build inputs)
patches/     patches over the upstream Harness source (series declares the order)
desktop/     Swift desktop shell (SPM: main app, uninstall helper, shared core)
scripts/     build / runtime smoke test / uninstall scripts
deepseek-harness-master.zip  immutable upstream 0.1.0-rc.5 source
dist/        build outputs (not committed)
```

## Upstream attribution

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 0.1.0-rc.5, MIT License, © 2026 DeepSeek.
- Node.js 24.18.0 (redistributed with the app); see `desktop/Resources/THIRD-PARTY-NOTICES.txt` for the remaining components.

## Publishing to GitHub

1. Create a public repository on GitHub (without auto-generated files).
2. Add the remote and push:

```sh
git remote add origin https://github.com/<you>/<repo>.git
git branch -M main
git push -u origin main
```

3. For releases, attach `dist/DeepSeek-Harness-macos-arm64.zip` as a Release asset (the CI build workflow produces the same artifact).

## License

[MIT](LICENSE) © 2026 DeepSeek Harness Desktop contributors
