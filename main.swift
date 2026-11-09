import Cocoa
import ApplicationServices

let appsPath = "/System/Applications/Apps.app"

// MARK: - 动作

enum CornerAction: String, CaseIterable {
    case none, missionControl, launchpad, notificationCenter
    case screenSaver, sleepDisplay, showDesktop, lockScreen

    var title: String {
        switch self {
        case .none: return "无"
        case .missionControl: return "调度中心"
        case .launchpad: return "启动台"
        case .notificationCenter: return "通知中心"
        case .screenSaver: return "屏幕保护程序"
        case .sleepDisplay: return "关闭显示器"
        case .showDesktop: return "显示桌面"
        case .lockScreen: return "锁定屏幕"
        }
    }

    func perform() {
        switch self {
        case .none:
            break
        case .missionControl:
            openApp("/System/Applications/Mission Control.app")
        case .launchpad:
            // macOS 26 起启动台被 "App"（Apps.app）取代，旧路径可能不存在
            if FileManager.default.fileExists(atPath: appsPath) {
                openApp(appsPath)
            } else {
                openApp("/System/Applications/Launchpad.app")
            }
        case .notificationCenter:
            shell("/usr/bin/open", ["-b", "com.apple.notificationcenterui"])
            log("open notificationcenterui")
        case .screenSaver:
            openApp("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .sleepDisplay:
            shell("/usr/bin/pmset", ["displaysleepnow"])
        case .showDesktop:
            shell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to key code 103"])
        case .lockScreen:
            shell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"])
        }
    }

    private func openApp(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            log("open failed: missing \(path)")
            return
        }
        let ok = NSWorkspace.shared.open(URL(fileURLWithPath: path))
        log("open \(path) -> \(ok)")
    }
}

func shell(_ launchPath: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    try? p.run()
}

// MARK: - 状态

let defaults = UserDefaults.standard

final class Store {
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    var size: CGFloat {
        get { CGFloat(defaults.object(forKey: "size") as? Double ?? 10) }
        set { defaults.set(Double(newValue), forKey: "size") }
    }
    var modifier: CGEventFlags {
        get { CGEventFlags(rawValue: UInt64(defaults.object(forKey: "modifier") as? Int ?? 0)) }
        set { defaults.set(Int(newValue.rawValue), forKey: "modifier") }
    }
    var swallow: Bool {
        get { defaults.object(forKey: "swallow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "swallow") }
    }
    var ignoreSystemBars: Bool {
        get { defaults.object(forKey: "ignoreSystemBars") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "ignoreSystemBars") }
    }

    let cornerIDs = ["tl", "tr", "bl", "br"]

    init() {
        guard defaults.object(forKey: "didSetup") == nil else { return }
        defaults.set(true, forKey: "didSetup")
        defaults.set(10.0, forKey: "size")
        setAction(.missionControl, for: "tl")
        setAction(.notificationCenter, for: "tr")
        setAction(.screenSaver, for: "bl")
        setAction(.launchpad, for: "br")
    }

    func action(for corner: String) -> CornerAction {
        CornerAction(rawValue: defaults.string(forKey: "corner.\(corner)") ?? "") ?? .none
    }

    func setAction(_ action: CornerAction, for corner: String) {
        defaults.set(action.rawValue, forKey: "corner.\(corner)")
    }
}

let store = Store()

// MARK: - 日志

func log(_ message: String) {
    let line = "\(Date().formatted(.iso8601)) \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/CornerClick.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - 角落判定

func modifiersMatch(_ flags: CGEventFlags) -> Bool {
    let wanted = store.modifier
    if wanted.isEmpty { return true }
    return flags.intersection(wanted) == wanted
}

func cornerHit() -> String? {
    let p = NSEvent.mouseLocation
    let s = store.size
    for screen in NSScreen.screens {
        let f = screen.frame.insetBy(dx: -1, dy: -1)
        guard f.contains(p) else { continue }
        if store.ignoreSystemBars {
            if p.y >= screen.visibleFrame.maxY { return nil }   // 菜单栏
            if p.y <= screen.visibleFrame.minY { return nil }   // Dock
        }
        let left = p.x - f.minX
        let right = f.maxX - p.x
        let bottom = p.y - f.minY
        let top = f.maxY - p.y
        if top <= s && left <= s { return "tl" }
        if top <= s && right <= s { return "tr" }
        if bottom <= s && left <= s { return "bl" }
        if bottom <= s && right <= s { return "br" }
    }
    return nil
}

// MARK: - 全局点击监听

var tapPort: CFMachPort?

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .leftMouseDown, store.enabled, modifiersMatch(event.flags) else {
        return Unmanaged.passUnretained(event)
    }
    guard let corner = cornerHit() else { return Unmanaged.passUnretained(event) }
    let action = store.action(for: corner)
    log("click at \(corner) -> \(action.rawValue)")
    guard action != .none else { return Unmanaged.passUnretained(event) }
    action.perform()
    return store.swallow ? nil : Unmanaged.passUnretained(event)
}

@discardableResult
func startTap() -> Bool {
    if tapPort == nil {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        tapPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        )
        if let port = tapPort {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            log("event tap ready")
        } else {
            log("event tap unavailable (AXIsProcessTrusted=\(AXIsProcessTrusted()))")
        }
    }
    return tapPort != nil
}

// MARK: - 菜单

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    var retry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays",
                                     accessibilityDescription: "CornerClick")
        rebuildMenu()
        if startTap() { return }
        requestAccessibility()
        showPermissionAlert()
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard tapPort == nil else { return }
            if startTap() { self.rebuildMenu() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if tapPort == nil { startTap() }
    }

    func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CornerClick 需要辅助功能权限"
        alert.informativeText = "没有这个权限时无法监听全局点击，角落点击不会有任何反应。如果列表里已经有旧的 CornerClick，先选中它点「−」删掉，再重新打开本 App 让它重新出现，然后勾选。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let running = tapPort != nil
        let status = NSMenuItem(title: running ? "状态：已接管鼠标" : "状态：等待辅助功能权限",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enable = NSMenuItem(title: "启用", action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = store.enabled ? .on : .off
        menu.addItem(enable)
        menu.addItem(.separator())

        menu.addItem(submenu("触发区大小", options: [6, 10, 16, 24].map { (CGFloat($0), "\($0) pt") },
                             current: store.size,
                             selector: #selector(setSize(_:))))

        let mods: [(CGEventFlags, String)] = [
            ([], "无（直接点击）"),
            (.maskShift, "⇧ Shift"),
            (.maskControl, "⌃ Control"),
            (.maskAlternate, "⌥ Option"),
            (.maskCommand, "⌘ Command"),
        ]
        let modifierItem = NSMenuItem(title: "点击时要求", action: nil, keyEquivalent: "")
        let modifierMenu = NSMenu()
        for (flag, name) in mods {
            let mi = NSMenuItem(title: name, action: #selector(setModifier(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = Int(flag.rawValue)
            mi.state = store.modifier == flag ? .on : .off
            modifierMenu.addItem(mi)
        }
        modifierItem.submenu = modifierMenu
        menu.addItem(modifierItem)

        let swallow = NSMenuItem(title: "吞掉角落点击", action: #selector(toggleSwallow), keyEquivalent: "")
        swallow.target = self
        swallow.state = store.swallow ? .on : .off
        menu.addItem(swallow)

        let bars = NSMenuItem(title: "忽略菜单栏与 Dock", action: #selector(toggleBars), keyEquivalent: "")
        bars.target = self
        bars.state = store.ignoreSystemBars ? .on : .off
        menu.addItem(bars)

        menu.addItem(.separator())

        let names = ["tl": "左上", "tr": "右上", "bl": "左下", "br": "右下"]
        for id in store.cornerIDs {
            let sub = NSMenuItem(title: names[id] ?? id, action: nil, keyEquivalent: "")
            let sm = NSMenu()
            let current = store.action(for: id)
            for (index, action) in CornerAction.allCases.enumerated() {
                let mi = NSMenuItem(title: action.title, action: #selector(pickAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = index
                mi.representedObject = id
                mi.state = action == current ? .on : .off
                sm.addItem(mi)
            }
            sub.submenu = sm
            menu.addItem(sub)
        }

        menu.addItem(.separator())

        let perm = NSMenuItem(title: "重新授权辅助功能…", action: #selector(grantAccessibility), keyEquivalent: "")
        perm.target = self
        menu.addItem(perm)

        let quit = NSMenuItem(title: "退出 CornerClick", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
    }

    func submenu(_ title: String, options: [(CGFloat, String)], current: CGFloat,
                 selector: Selector) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (value, name) in options {
            let mi = NSMenuItem(title: name, action: selector, keyEquivalent: "")
            mi.target = self
            mi.representedObject = Double(value)
            mi.state = current == value ? .on : .off
            menu.addItem(mi)
        }
        root.submenu = menu
        return root
    }

    @objc func toggleEnabled() {
        store.enabled.toggle()
        rebuildMenu()
    }

    @objc func setSize(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double { store.size = CGFloat(v) }
        rebuildMenu()
    }

    @objc func setModifier(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Int {
            store.modifier = CGEventFlags(rawValue: UInt64(v))
        }
        rebuildMenu()
    }

    @objc func toggleSwallow() {
        store.swallow.toggle()
        rebuildMenu()
    }

    @objc func toggleBars() {
        store.ignoreSystemBars.toggle()
        rebuildMenu()
    }

    @objc func pickAction(_ sender: NSMenuItem) {
        guard let corner = sender.representedObject as? String else { return }
        let action = CornerAction.allCases[sender.tag]
        store.setAction(action, for: corner)
        rebuildMenu()
    }

    @objc func grantAccessibility() {
        requestAccessibility()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        if startTap() { rebuildMenu() }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
