# Release Checklist / 发布清单

## Before Tagging / 打标签前

- Confirm the upstream ZIP SHA-256 and Node.js SHA-256 in `config/build-versions.env`.
- Run the complete build on an Apple Silicon Mac:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/build-app.sh
```

- Confirm `xcrun swift test`, Harness tests, runtime smoke test, and
  `codesign --verify --deep --strict` pass.
- Scan tracked files for API keys, credentials, personal paths, workspace files,
  and generated output. Never stage `build/`, `dist/`, Application Support,
  `.dsh`, `.agents`, or user workspaces.
- Review `NOTICE.md`, `LICENSE`, `SECURITY.md`, and the bilingual About text.

## Tag and Release / 标签与发布

Desktop 3 uses the tag `v0.1.0-rc.5-desktop.3`. The tag workflow builds a fresh
App and uploads the arm64 ZIP plus a SHA-256 checksum. Public artifacts are
ad-hoc signed and not notarized; do not describe them as Apple-verified.

Desktop 3 使用标签 `v0.1.0-rc.5-desktop.3`。标签工作流会重新构建 App，并上传
arm64 ZIP 与 SHA-256 校验文件。公开产物使用 ad-hoc 签名且未公证，不得描述为
Apple 已验证软件。

## Release Notes / 发布说明

Include the following in each release:

- upstream Harness version and desktop build number;
- macOS minimum version and arm64 requirement;
- checksum and signing/notarization status;
- uninstall modes and the warning that Complete permanently deletes workspaces;
- links to `NOTICE.md`, `SECURITY.md`, and the upstream Harness project.
