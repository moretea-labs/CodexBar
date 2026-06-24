# CodexBar 打包与分发

## 选择 DMG 还是 PKG

- **DMG（推荐）**：用户打开磁盘镜像，把 `CodexBar.app` 拖到 `Applications`。
- **PKG**：通过 macOS Installer 安装到 `/Applications`。适合企业部署、安装脚本或多组件产品。

## 1. 仅自己使用：创建免公证 DMG

```bash
./scripts/package_dmg.sh
```

输出：

```text
build/CodexBar-0.1.0.dmg
```

该构建使用 ad-hoc 签名，只适合本机开发或受控测试。通过浏览器、聊天工具等传给其他 Mac 后，Gatekeeper 可能阻止直接打开。

## 2. 面向其他用户：Developer ID 签名和公证

需要 Apple Developer Program 账号，并在钥匙串中安装：

- `Developer ID Application`：签署 `.app` 和可选的 `.dmg`。
- `Developer ID Installer`：签署 `.pkg`。

查看本机身份：

```bash
security find-identity -v -p codesigning
```

先把公证凭据保存到钥匙串（只需执行一次）：

```bash
xcrun notarytool store-credentials "CodexBar-Notary" \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID" \
  --password "App 专用密码"
```

### 签名、公证 DMG

```bash
SIGN_IDENTITY="Developer ID Application: 你的名称 (TEAMID)" \
NOTARY_PROFILE="CodexBar-Notary" \
./scripts/package_dmg.sh
```

脚本会依次：

1. Release 编译。
2. 使用 Hardened Runtime 和 `CodexBar.entitlements` 签署 App。
3. 创建带 `Applications` 快捷方式的 DMG。
4. 签署 DMG。
5. 提交 Apple 公证并等待结果。
6. 将公证票据 staple 到 DMG。

### 签名、公证 PKG

```bash
SIGN_IDENTITY="Developer ID Application: 你的名称 (TEAMID)" \
INSTALLER_IDENTITY="Developer ID Installer: 你的名称 (TEAMID)" \
NOTARY_PROFILE="CodexBar-Notary" \
./scripts/package_pkg.sh
```

## 3. 不公证的本地 PKG

```bash
./scripts/package_pkg.sh
```

生成的 PKG 未使用 Developer ID Installer 签名，仅适合本机测试。

## 4. 验证

验证 App 签名：

```bash
codesign --verify --deep --strict --verbose=4 build/CodexBar.app
spctl --assess --type execute --verbose=4 build/CodexBar.app
```

验证 DMG 公证票据：

```bash
xcrun stapler validate build/CodexBar-0.1.0.dmg
```

验证 PKG：

```bash
pkgutil --check-signature build/CodexBar-0.1.0.pkg
spctl --assess --type install --verbose=4 build/CodexBar-0.1.0.pkg
```

## 注意

- `build_app.sh` 没有设置 `SIGN_IDENTITY` 时会使用 ad-hoc 签名。
- 公证必须使用 Developer ID 签名，ad-hoc 或开发证书不能用于正式分发。
- CodexBar 需要 Apple Events 权限来控制 Terminal；签名时必须保留工程中的 entitlements。
