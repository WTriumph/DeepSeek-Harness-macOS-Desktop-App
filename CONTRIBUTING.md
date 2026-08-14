# Contributing

感谢你的贡献！Thanks for contributing!

## 行为准则

请保持友善、尊重他人；提交内容默认按仓库许可证（MIT）授权。

## 构建与测试

```sh
# 完整构建（含全量测试、冒烟测试、签名、打包）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/build-app.sh

# 仅桌面壳测试（需要 Xcode 命令行工具）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test
```

快速构建（跳过大部分 Harness 测试，只跑关键生产路径）：

```sh
DSH_FAST_BUILD=1 ./scripts/build-app.sh
```

## 修改 Harness 上游源码

上游源码以不可变 ZIP（`deepseek-harness-master.zip`）为准，**不要直接改解压目录**。流程：

1. 在 `build/macos-arm64/source/deepseek-harness-master`（或全新解压）里完成修改与测试。
2. 以全新解压的源码为基线生成统一 diff（git-style，路径 `a/...` `b/...`），命名为 `patches/harness/NNNN-简短说明.patch`。
3. 追加到 `patches/harness/series`（一个文件名一行，按应用顺序）。
4. 在全新解压目录上验证 `patch -p1 --forward` 按序全部应用成功，再跑一次完整构建。
5. 修改上游代码的同时，同步更新其测试与相关断言（仓库约定：测试描述行为，行为变了测试一起变）。

## 桌面壳（Swift）约定

- 面向用户的文字用中文；代码注释与标识符用英文。
- 核心逻辑放在 `desktop/Sources/HarnessDesktopCore`，配套单元测试放在 `desktop/Tests/HarnessDesktopCoreTests`。
- 涉及数据删除/迁移的逻辑必须保留"只操作白名单路径"的防护，并加测试。

## 提交信息

- 建议格式：`<类型>: <简述>`（如 `fix:`, `feat:`, `docs:`, `build:`）。
- 一个提交只做一件事；修复 bug 时附上根因说明。

## 版权

贡献代码即表示你同意按仓库 [MIT 许可证](LICENSE) 授权。版权归属 "DeepSeek Harness Desktop contributors"。
