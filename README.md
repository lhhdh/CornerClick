# CornerClick

把 macOS 触发角（Hot Corners）从「鼠标划过就触发」改成「移到角落**并点击**才触发」的轻量菜单栏工具。

> macOS 自带的触发角只有悬停触发，唯一的附加条件是按住修饰键，没有「点击才触发」这个选项。CornerClick 用一个全局鼠标监听加角落命中判定，把这一行为补上：单文件 Swift 实现，无任何第三方依赖，不占 Dock，配置保存在 `UserDefaults`。

*CornerClick turns macOS Hot Corners into click-to-trigger corners. Single-file Swift, no dependencies. Requires macOS 13+.*

---

## 为什么需要它

系统触发角在你把鼠标甩向屏幕边缘时会误触发——想点关闭按钮、想拖窗口到边上、想把鼠标挪出屏幕，都会顺带把调度中心或启动台弹出来。系统设置里只能给触发角加一个「修饰键」条件，没法要求真正的点击动作。

CornerClick 把触发条件改成：**鼠标在角落判定区内 + 按下左键**。移动过去不动，什么都不会发生。

## 功能

- **点击触发**：只有左键按下且落点在角落区域时才执行动作
- **四个角独立配置**：每个角可以指定不同动作，也可以设为「无」
- **修饰键条件**：可选要求同时按住 ⇧ / ⌃ / ⌥ / ⌘，用来进一步防误触
- **触发区大小可调**：6 / 10 / 16 / 24 pt
- **可吞掉角落点击**：开启后那一下点击不再传给下面的窗口（不会顺带点到 Dock 图标或苹果菜单）
- **可选忽略菜单栏与 Dock**：避免把菜单栏、Dock 区域内的点击误判成角落
- **多显示器**：按点击发生的那块屏幕判定，每块屏幕的四个角都有效
- **纯菜单栏**：`LSUIElement` 后台应用，不占 Dock、不进 ⌘Tab
- **配置持久化**：重启后保留

## 系统要求

- macOS 13 或更高（开发与验证环境为 macOS 27）
- Apple Silicon 或 Intel
- 编译需要 Xcode 或 Command Line Tools（`swiftc`）

## 安装

### 从源码编译

```sh
git clone https://github.com/lhhdh/CornerClick.git
cd CornerClick
./build.sh
cp -R build/CornerClick.app /Applications/
open /Applications/CornerClick.app
```

`build.sh` 会用本机可用的代码签名证书签名：能找到 `Apple Development` 证书就用它，否则退回到 ad-hoc 签名。签名方式会影响辅助功能授权在重新编译后是否保留，见[常见问题](#常见问题)。

### 首次运行

首次启动会请求**辅助功能**权限（Accessibility）。没有这个权限时无法创建全局事件监听，角落点击不会有任何反应。

授权路径：系统设置 › 隐私与安全性 › 辅助功能 › 勾选 CornerClick。

菜单第一行会显示当前状态：

- `状态：已接管鼠标` —— 权限已生效，监听器在运行
- `状态：等待辅助功能权限` —— 权限未生效，此时点击角落不会有反应

## 使用

菜单栏出现光标图标后点击打开菜单：

| 菜单项 | 说明 |
|---|---|
| 状态 | 监听器是否已经拿到权限并运行 |
| 启用 | 总开关，关闭后点击判定完全停止 |
| 触发区大小 | 角落判定的边长，以屏幕边缘向内计算的像素数 |
| 点击时要求 | 无（直接点击）/ ⇧ Shift / ⌃ Control / ⌥ Option / ⌘ Command |
| 吞掉角落点击 | 开启后，命中的那一下点击不会传给下层应用 |
| 忽略菜单栏与 Dock | 开启后，落在菜单栏、Dock 区域内的点击不算角落 |
| 左上 / 右上 / 左下 / 右下 | 为每个角指定动作 |
| 重新授权辅助功能… | 打开系统设置的辅助功能面板并重试创建监听器 |
| 退出 CornerClick | 退出应用 |

可选动作：

| 动作 | 实际执行 |
|---|---|
| 无 | 不执行 |
| 调度中心 | 打开 `/System/Applications/Mission Control.app` |
| 启动台 | 打开 `/System/Applications/Apps.app`；旧系统回退到 `/System/Applications/Launchpad.app` |
| 通知中心 | `open -b com.apple.notificationcenterui`（见[已知限制](#已知限制)） |
| 屏幕保护程序 | 打开 `ScreenSaverEngine.app` |
| 关闭显示器 | `pmset displaysleepnow` |
| 显示桌面 | 通过 System Events 发送 F11 |
| 锁定屏幕 | 通过 System Events 发送 ⌃⌘Q |

默认配置：左上=调度中心、右上=通知中心、左下=屏幕保护程序、右下=启动台。

> macOS 26 起系统把启动台换成了新的「App」网格（`/System/Applications/Apps.app`，bundle id `com.apple.apps.launcher`），旧的 `Launchpad.app` 已不存在。CornerClick 按新路径优先、旧路径回退处理。

## 关闭系统自带触发角

系统触发角和 CornerClick 会同时生效，不关掉就会出现「划过去已经触发，再点一次又触发」的双重响应。命令行关闭：

```sh
for c in tl tr bl br; do defaults write com.apple.dock wvous-$c-corner -int 0; done
killall Dock
```

也可以走图形界面：系统设置 › 桌面与程序坞 › 触发角，把四个角都设为「—」。

## 工作原理

1. **全局点击监听**：用 `CGEventTap` 在 `.cgSessionEventTap` 上监听 `leftMouseDown`。tap 建在 `.headInsertEventTap` 位置，因此点击在分发到目标应用之前就能被判断；选择「吞掉角落点击」时直接返回 `nil` 丢弃事件。
2. **角落判定**：读取 `NSEvent.mouseLocation`（Cocoa 全局坐标，原点在主屏左下角），遍历 `NSScreen.screens`，找到点击所在的屏幕，计算该点到四条边的距离；两个方向都落在判定区内才算命中角落。
3. **动作执行**：按角落查表，在一条**串行后台队列**上执行，用 `open(1)` 打开系统 App，或调用 `pmset` / `osascript`。动作不在主线程上跑，避免阻塞事件 tap 的回调——这是连点时丢点击的主要原因。
4. **权限与签名**：macOS 的 TCC 把辅助功能授权绑定到「代码要求」上。ad-hoc 签名的代码要求里钉死二进制哈希，每次重编译都会被当成一个新程序，之前的勾选失效；用真实证书（如 Apple Development）签名时要求是「标识 + 证书」，重编译后授权仍然有效。CornerClick 的 `build.sh` 优先使用证书签名。
5. **恢复监听**：系统在超时或用户输入后会临时禁用事件 tap，回调里收到 `tapDisabledByTimeout` / `tapDisabledByUserInput` 时立即重新启用；权限尚未授予时每 2 秒重试一次。

## 与其它方案对比

| | 系统触发角 | CornerClick | Hammerspoon | BetterTouchTool |
|---|---|---|---|---|
| 点击才触发 | ✗ | ✓ | 需自己写 Lua | 触发条件更丰富 |
| 额外依赖 | 无 | 无 | Hammerspoon 运行时 | 付费应用 |
| 配置方式 | 图形界面 | 菜单栏 | 脚本 | 图形界面 |
| 开源 | — | MIT | MIT | 闭源 |

## 常见问题

**点了角落没反应，怎么查？**

动作执行和命中判定都会写到 `/tmp/CornerClick.log`：

```sh
tail -f /tmp/CornerClick.log
```

正常一次触发会留下两行：

```
18:22:06.412 fire br -> launchpad
18:22:06.451 open /System/Applications/Apps.app exit=0 38ms
```

- 只有 `click at ... -> none`：该角配置的是「无」
- `open ... -> false`：系统拒绝了打开请求
- `open failed: missing ...`：目标 App 在该系统版本上不存在
- 连 `click at ...` 都没有：事件 tap 没建起来，看下一节

**菜单显示「等待辅助功能权限」怎么办？**

1. 系统设置 › 隐私与安全性 › 辅助功能，确认 CornerClick 已勾选
2. 列表里如果有多条 CornerClick，删掉多余的，只保留当前这一条
3. 仍然不行就重启 App：`pkill -f CornerClick.app && open /Applications/CornerClick.app`

**重新编译后要重新授权吗？**

- 用 `Apple Development` 证书签名：不用
- 用 ad-hoc 签名：要。哈希变了，旧授权不再匹配

**为什么主屏上边两个角不生效？**

它们落在菜单栏里。默认「忽略菜单栏与 Dock」是关闭的，所以点击能生效，但那一下点击如果不吞掉就会同时点到菜单栏。想彻底避开菜单栏就打开这个开关，代价是主屏上边两角失效。

**Dock 在右侧且自动隐藏，右下角点击时 Dock 会弹出来**

这是系统行为：鼠标贴到屏幕右缘时 Dock 弹出。开启「吞掉角落点击」可以保证那一下不会点到 Dock 图标，但视觉上仍会看到 Dock 出现。把触发区调小可以缓解。

## 已知限制

- **通知中心动作无效**：`com.apple.notificationcenterui` 是后台 agent，`open -b` 返回 0 但不会弹出面板，需要换个实现方式
- **显示桌面 / 锁定屏幕**走 `osascript` 调 System Events，首次会请求「自动化」权限
- **主屏上边两角与菜单栏重叠**，见上文
- 未做公证（notarization），仅适合自行编译使用

## 开发

```
.
├── main.swift    # 全部实现：动作、配置、角落判定、事件监听、菜单
├── Info.plist    # LSUIElement 后台应用
├── build.sh      # 编译 + 打包 + 签名
└── README.md
```

```sh
./build.sh                 # 产出 build/CornerClick.app
swiftc -typecheck main.swift   # 只做类型检查
```

代码结构：`CornerAction`（动作表）→ `Store`（配置读写）→ `cornerHit()`（角落判定）→ `tapCallback`（全局监听）→ `AppDelegate`（菜单与生命周期）。

## License

[MIT](LICENSE)
