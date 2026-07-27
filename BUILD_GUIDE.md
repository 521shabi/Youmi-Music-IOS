# Youmi-Music-IOS 构建指南

## 一、API 服务器搭建

### 1.1 启动本地服务器

```bash
cd ../netease-api-server
node app.js
```

服务器将在 `http://localhost:3000` 运行。

### 1.2 服务器配置说明

修改 `NeteaseMusic/NeteaseMusic/Services/APIConfig.swift`:
```swift
static var baseURL: String = "http://localhost:3000"
```

修改 `NeteaseMusic/NeteaseMusic/Services/MusicSourceConfig.swift`:
```swift
let neteaseApiURL = "http://localhost:3000/song/url"
```

**真机调试注意**：将 `localhost` 替换为电脑的 IP 地址（如 `http://192.168.1.100:3000`）

---

## 二、使用 GitHub Actions 构建 IPA

### 2.1 创建自己的仓库

1. 打开 https://github.com/new
2. 创建一个名为 `Youmi-Music-IOS` 的私有仓库
3. 不要勾选 "Initialize this repository with a README"

### 2.2 推送代码

```bash
cd Youmi-Music-IOS
git remote set-url origin https://github.com/你的用户名/Youmi-Music-IOS.git
git push -u origin main
```

### 2.3 触发构建

1. 打开 https://github.com/你的用户名/Youmi-Music-IOS/actions
2. 选择 "Build iOS IPA"
3. 点击 "Run workflow"

### 2.4 下载 IPA

构建完成后：
1. 在 Actions 页面点击最新的运行
2. 向下滚动到 "Artifacts" 部分
3. 下载 `NeteaseMusic-IPA`

---

## 三、使用 macOS 本地构建

### 3.1 环境要求

- macOS 13+
- Xcode 15+
- iOS SDK 15.0+

### 3.2 编译步骤

```bash
cd Youmi-Music-IOS/NeteaseMusic

# 方案一：使用模拟器构建
xcodebuild build \
  -project NeteaseMusic.xcodeproj \
  -scheme NeteaseMusic \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# 方案二：生成 IPA（需要 Apple Developer 账号）
xcodebuild archive \
  -project NeteaseMusic.xcodeproj \
  -scheme NeteaseMusic \
  -destination 'generic/platform=iOS' \
  -archivePath build/NeteaseMusic.xcarchive \
  -configuration Release

xcodebuild -exportArchive \
  -archivePath build/NeteaseMusic.xcarchive \
  -exportPath build/IPA \
  -exportOptionsPlist ExportOptions.plist
```

---

## 四、安装 IPA 到设备

### 4.1 使用 AltStore

1. 在 iPhone 上安装 AltStore
2. 将 IPA 文件发送到 iPhone
3. 用 AltStore 打开 IPA 文件进行安装

### 4.2 使用 Xcode

1. 连接 iPhone 到电脑
2. 在 Xcode 中选择你的设备
3. 点击 Run 按钮

### 4.3 使用 Sideloadly

1. 下载 Sideloadly（https://sideloadly.io/）
2. 连接 iPhone 到电脑
3. 拖放 IPA 文件到 Sideloadly

---

## 五、常见问题

### Q1: 服务器连接失败

确保：
- API 服务器正在运行
- 手机和电脑在同一局域网
- 防火墙允许 3000 端口访问

### Q2: 无法登录网易云音乐

自建服务器使用官方 API，登录需要网易云音乐账号密码。

### Q3: 构建时出现代码签名错误

在 Xcode 中：
- 选择项目 → Signing & Capabilities
- 取消勾选 "Automatically manage signing"
- 或选择你的开发团队

### Q4: IPA 安装后无法打开

需要在 iPhone 设置中信任开发者：
- 设置 → 通用 → VPN 与设备管理
- 找到你的开发者证书并信任

---

## 六、项目结构

```
Youmi-Music-IOS/
├── NeteaseMusic/
│   ├── NeteaseMusic/
│   │   ├── Services/
│   │   │   ├── APIConfig.swift      # API 地址配置
│   │   │   ├── MusicSourceConfig.swift  # 音乐源配置
│   │   │   └── MusicService.swift   # 音乐服务
│   │   └── NeteaseMusic.xcodeproj   # Xcode 项目
│   ├── ExportOptions.plist          # 导出配置
│   └── ExportOptions-GHA.plist      # GitHub Actions 导出配置
├── .github/workflows/
│   └── build-ipa.yml                # 自动构建流程
└── BUILD_GUIDE.md                   # 本指南
```

---

## 七、技术支持

如有问题，请参考：
- 原始仓库：https://github.com/7DaysMax/Youmi-Music-IOS
- API 服务器：https://github.com/Binaryify/NeteaseCloudMusicApi
