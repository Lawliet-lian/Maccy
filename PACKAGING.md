# Maccy 打包与安装说明

这份说明适用于在本机打包和安装定制版 Maccy。需要安装 Xcode。本机自用无需 Apple 开发者证书，脚本会使用本地签名（ad hoc）。

## 生成 Release 安装包

在仓库根目录运行：

```sh
./scripts/package-dmg.sh --configuration Release
```

脚本会重新构建 Release 版，从 Xcode 工程读取版本号和构建号，为应用重新签名，然后生成 DMG。可以直接运行脚本，省去在 Xcode 里先点 Run 的步骤。

默认产物为 `dist/Maccy-<版本号>.dmg`。例如，版本 **2.3.3** 的产物是 `dist/Maccy-2.3.3.dmg`。终端最后的 `DMG:` 一行会显示完整路径。重新打包同一版本会覆盖原来的同名 DMG。

发新版本时，在 Xcode 的 Maccy target 中更新 **Version** 和 **Build**，让 Debug 和 Release 使用相同的值。

## 替换已安装的 Maccy

1. 在旧版的「偏好设置 → 高级」确认「退出时清除历史记录」未勾选，然后从菜单栏完全退出 Maccy。
2. 替换前备份整个 `~/Library/Application Support/Maccy/` 目录。
3. 双击生成的 DMG，把里面的 `Maccy.app` 拖入「应用程序」，确认替换旧版。
4. 从「应用程序」打开 Maccy，在「关于」核对版本，再查看历史记录和置顶项是否保留。

如果替换后自动粘贴失效，打开 macOS「系统设置 → 隐私与安全性 → 辅助功能」，移除旧的 Maccy 条目，再添加当前的 `/Applications/Maccy.app` 并启用权限。
