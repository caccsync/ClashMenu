import AppKit
import Combine

@MainActor
final class NativeStatusMenuController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let statusContentView: StatusItemContentView
    private let menu = NSMenu()
    private let runtimeStatusItem = NSMenuItem()
    private let runtimeMenu = NSMenu()
    private let startItem = NSMenuItem()
    private let stopItem = NSMenuItem()
    private let restartItem = NSMenuItem()
    private let modeItem = NSMenuItem()
    private let modeMenu = NSMenu()
    private let ruleModeItem = NSMenuItem()
    private let globalModeItem = NSMenuItem()
    private let directModeItem = NSMenuItem()
    private let configItem = NSMenuItem()
    private let configMenu = NSMenu()
    private let systemProxyItem = NSMenuItem()
    private let tunModeItem = NSMenuItem()
    private let openDashboardItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let aboutItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private let settingsWindowController: NativeSettingsWindowController

    private var observers: [AnyCancellable] = []
    private var lastLanguage: AppLanguage?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusContentView = StatusItemContentView(frame: .zero)
        self.settingsWindowController = NativeSettingsWindowController(appState: appState)

        super.init()

        self.configureStatusItem()
        self.configureMenu()
        self.bindState()
        self.refreshAllUI(rebuildConfigMenu: true)
    }

    func shutdown() {
        self.observers.forEach { $0.cancel() }
        self.observers.removeAll()
        NSStatusBar.system.removeStatusItem(self.statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == self.menu {
            self.appState.reloadConfigFileList()
            self.appState.refreshLaunchAtLoginStatus()
            self.refreshAllUI(rebuildConfigMenu: true)
        } else if menu == self.runtimeMenu {
            self.refreshRuntimeMenu()
        } else if menu == self.modeMenu {
            self.refreshModeMenu()
        } else if menu == self.configMenu {
            self.refreshConfigMenu()
        }
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }

        button.image = nil
        button.title = ""
        self.statusContentView.frame = button.bounds
        self.statusContentView.autoresizingMask = [.width, .height]
        button.addSubview(self.statusContentView)

        self.statusItem.menu = self.menu
    }

    private func configureMenu() {
        self.menu.autoenablesItems = false
        self.runtimeMenu.autoenablesItems = false
        self.modeMenu.autoenablesItems = false
        self.configMenu.autoenablesItems = false
        self.menu.delegate = self
        self.runtimeMenu.delegate = self
        self.modeMenu.delegate = self
        self.configMenu.delegate = self

        self.runtimeStatusItem.submenu = self.runtimeMenu
        self.modeItem.submenu = self.modeMenu
        self.configItem.submenu = self.configMenu

        self.startItem.target = self
        self.startItem.action = #selector(self.startCore(_:))
        self.stopItem.target = self
        self.stopItem.action = #selector(self.stopCore(_:))
        self.restartItem.target = self
        self.restartItem.action = #selector(self.restartCore(_:))
        self.runtimeMenu.items = [self.startItem, self.stopItem, self.restartItem]

        self.ruleModeItem.target = self
        self.ruleModeItem.action = #selector(self.switchMode(_:))
        self.ruleModeItem.representedObject = CoreMode.rule.rawValue
        self.globalModeItem.target = self
        self.globalModeItem.action = #selector(self.switchMode(_:))
        self.globalModeItem.representedObject = CoreMode.global.rawValue
        self.directModeItem.target = self
        self.directModeItem.action = #selector(self.switchMode(_:))
        self.directModeItem.representedObject = CoreMode.direct.rawValue
        self.modeMenu.items = [self.ruleModeItem, self.globalModeItem, self.directModeItem]

        self.systemProxyItem.target = self
        self.systemProxyItem.action = #selector(self.toggleSystemProxy(_:))
        self.tunModeItem.target = self
        self.tunModeItem.action = #selector(self.toggleTunMode(_:))
        self.openDashboardItem.target = self
        self.openDashboardItem.action = #selector(self.openDashboard(_:))
        self.settingsItem.target = self
        self.settingsItem.action = #selector(self.openSettings(_:))
        self.aboutItem.target = self
        self.aboutItem.action = #selector(self.showAbout(_:))
        self.quitItem.target = self
        self.quitItem.action = #selector(self.quitApp(_:))

        self.menu.items = [
            self.runtimeStatusItem,
            self.modeItem,
            self.configItem,
            .separator(),
            self.systemProxyItem,
            self.tunModeItem,
            self.openDashboardItem,
            .separator(),
            self.settingsItem,
            self.aboutItem,
            .separator(),
            self.quitItem,
        ]
    }

    private func bindState() {
        self.observers = [
            self.appState.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshAllUI(rebuildConfigMenu: false)
                }
            },
        ]
    }

    private func refreshAllUI(rebuildConfigMenu: Bool) {
        self.refreshStatusItemDisplay()
        self.refreshRuntimeMenu()
        self.refreshModeMenu()
        self.refreshToggleItems()
        self.refreshStaticTitlesIfNeeded()
        if rebuildConfigMenu || self.lastLanguage != self.appState.uiLanguage {
            self.refreshConfigMenu()
        }
        self.lastLanguage = self.appState.uiLanguage
    }

    private func refreshStatusItemDisplay() {
        let display = self.appState.menuBarDisplaySnapshot
        self.statusContentView.apply(display: display)
        let requiredWidth = self.statusContentView.requiredWidth
        if abs(self.statusItem.length - requiredWidth) > 0.5 {
            self.statusItem.length = requiredWidth
        }
    }

    private func refreshRuntimeMenu() {
        let running = self.appState.processManager.isRunning
        self.runtimeStatusItem.attributedTitle = nil
        self.runtimeStatusItem.title = self.appState.runtimeStatusText
        self.runtimeStatusItem.state = running ? .on : .off
        self.runtimeStatusItem.onStateImage = self.runtimeIndicatorImage(color: .systemGreen)
        self.runtimeStatusItem.offStateImage = self.runtimeIndicatorImage(color: .secondaryLabelColor)

        self.startItem.title = self.local("启动", "Start")
        self.stopItem.title = self.tr("ui.action.stop")
        self.restartItem.title = self.local("重启", "Restart")

        let processing = self.appState.isCoreActionProcessing
        self.startItem.isEnabled = !processing && !running
        self.stopItem.isEnabled = !processing && running
        self.restartItem.isEnabled = !processing
    }

    private func refreshModeMenu() {
        self.modeItem.title = self.local("代理模式", "Proxy Mode")
        self.ruleModeItem.title = self.local("规则模式", "Rule Mode")
        self.globalModeItem.title = self.local("全局模式", "Global Mode")
        self.directModeItem.title = self.local("直连模式", "Direct Mode")

        let enabled = self.appState.isModeSwitchEnabled
        let currentMode = self.appState.currentMode
        self.ruleModeItem.state = currentMode == .rule ? .on : .off
        self.globalModeItem.state = currentMode == .global ? .on : .off
        self.directModeItem.state = currentMode == .direct ? .on : .off
        self.ruleModeItem.isEnabled = enabled
        self.globalModeItem.isEnabled = enabled
        self.directModeItem.isEnabled = enabled
    }

    private func refreshToggleItems() {
        self.systemProxyItem.title = self.tr("ui.quick.system_proxy")
        self.systemProxyItem.state = self.appState.isSystemProxyEnabled ? .on : .off
        self.systemProxyItem.isEnabled = self.appState.isRuntimeRunning && !self.appState.isProxySyncing

        self.tunModeItem.title = self.tr("ui.quick.tun_mode")
        self.tunModeItem.state = self.appState.desiredTunEnabled ? .on : .off
        self.tunModeItem.isEnabled = self.appState.isRuntimeRunning && !self.appState.isTunSyncing
    }

    private func refreshStaticTitlesIfNeeded() {
        self.configItem.title = self.local("配置文件", "Configurations")
        self.openDashboardItem.title = self.local("控制面板", "Dashboard")
        self.settingsItem.title = self.local("设置", "Settings")
        self.aboutItem.title = self.local("关于", "About")
        self.quitItem.title = self.tr("ui.action.quit")
    }

    private func refreshConfigMenu() {
        self.configMenu.removeAllItems()

        let listHeader = NSMenuItem(title: self.local("配置列表", "Config List"), action: nil, keyEquivalent: "")
        listHeader.isEnabled = false
        self.configMenu.addItem(listHeader)

        if self.appState.availableConfigFileNames.isEmpty {
            let emptyItem = NSMenuItem(title: self.local("无配置文件", "No Configurations"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            self.configMenu.addItem(emptyItem)
        } else {
            for fileName in self.appState.availableConfigFileNames {
                let item = NSMenuItem(title: fileName, action: #selector(self.selectConfig(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = fileName
                item.state = fileName == self.appState.selectedConfigName ? .on : .off
                self.configMenu.addItem(item)
            }
        }

        self.configMenu.addItem(.separator())

        let actionsHeader = NSMenuItem(title: self.local("常用操作", "Common Actions"), action: nil, keyEquivalent: "")
        actionsHeader.isEnabled = false
        self.configMenu.addItem(actionsHeader)

        self.configMenu.addItem(self.makeMenuItem(self.tr("ui.quick.reload_config_list"), action: #selector(self.reloadConfig(_:))))
        self.configMenu.addItem(self.makeMenuItem(self.tr("ui.quick.import_local_config"), action: #selector(self.importLocalConfig(_:))))
        self.configMenu.addItem(self.makeMenuItem(self.tr("ui.quick.import_remote_config"), action: #selector(self.importRemoteConfig(_:))))
        self.configMenu.addItem(self.makeMenuItem(self.tr("ui.quick.update_remote_configs"), action: #selector(self.updateRemoteConfigs(_:))))
        self.configMenu.addItem(self.makeMenuItem(self.tr("ui.quick.show_in_finder"), action: #selector(self.showInFinder(_:))))
    }

    private func makeMenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func runtimeIndicatorImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 1, y: 1, width: 8, height: 8)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        image.isTemplate = false
        return image
    }

    private func tr(_ key: String) -> String {
        L10n.t(key, language: self.appState.uiLanguage)
    }

    private func local(_ zh: String, _ en: String) -> String {
        self.appState.uiLanguage == .zhHans ? zh : en
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = self.local("操作失败", "Operation Failed")
        alert.informativeText = message
        alert.addButton(withTitle: self.tr("ui.action.ok"))
        self.appState.prepareModalWindowPresentation()
        self.appState.configureModalWindow(alert.window)
        alert.runModal()
    }

    @objc
    private func startCore(_ sender: Any?) {
        Task { @MainActor [weak self] in
            await self?.appState.startCore(trigger: .manual)
            self?.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func stopCore(_ sender: Any?) {
        Task { @MainActor [weak self] in
            await self?.appState.stopCore(trigger: .manual)
            self?.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func restartCore(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.appState.isRuntimeRunning {
                await self.appState.restartCore()
            } else {
                await self.appState.startCore(trigger: .manual)
            }
            self.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func switchMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = CoreMode(rawValue: rawValue) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message = await self.appState.switchMode(to: mode) {
                self.presentError(message)
            }
            self.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func selectConfig(_ sender: NSMenuItem) {
        guard let fileName = sender.representedObject as? String else { return }
        Task { @MainActor [weak self] in
            await self?.appState.selectConfigFile(named: fileName)
            self?.refreshAllUI(rebuildConfigMenu: true)
        }
    }

    @objc
    private func reloadConfig(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appState.reloadConfig()
            self.appState.reloadConfigFileList()
            self.refreshAllUI(rebuildConfigMenu: true)
        }
    }

    @objc
    private func importLocalConfig(_ sender: Any?) {
        self.appState.importLocalConfigFile()
        self.appState.reloadConfigFileList()
        self.refreshAllUI(rebuildConfigMenu: true)
    }

    @objc
    private func importRemoteConfig(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appState.importRemoteConfigFile()
            self.appState.reloadConfigFileList()
            self.refreshAllUI(rebuildConfigMenu: true)
        }
    }

    @objc
    private func updateRemoteConfigs(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appState.updateAllRemoteConfigFiles()
            self.appState.reloadConfigFileList()
            self.refreshAllUI(rebuildConfigMenu: true)
        }
    }

    @objc
    private func showInFinder(_ sender: Any?) {
        self.appState.showSelectedConfigInFinder()
    }

    @objc
    private func toggleSystemProxy(_ sender: Any?) {
        let target = !self.appState.isSystemProxyEnabled
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message = await self.appState.toggleSystemProxy(target) {
                self.presentError(message)
            }
            self.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func toggleTunMode(_ sender: Any?) {
        let target = !self.appState.desiredTunEnabled
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message = await self.appState.toggleTunMode(target) {
                self.presentError(message)
            }
            self.refreshAllUI(rebuildConfigMenu: false)
        }
    }

    @objc
    private func openDashboard(_ sender: Any?) {
        guard let url = self.appState.controllerDashboardURL(),
              NSWorkspace.shared.open(url)
        else {
            self.presentError(self.local("无法打开 Dashboard。", "Unable to open Dashboard."))
            return
        }
    }

    @objc
    private func openSettings(_ sender: Any?) {
        self.settingsWindowController.present()
    }

    @objc
    private func showAbout(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let mihomoVersion = await self.appState.resolvedMihomoVersionForDisplay()

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = self.local("关于 ClashMenu", "About ClashMenu")
            alert.informativeText = [
                "ClashMenu \(self.appVersionString())",
                "Mihomo \(mihomoVersion)",
                "Copyright (c) ClashMenu",
            ].joined(separator: "\n")
            alert.addButton(withTitle: self.tr("ui.action.ok"))
            alert.addButton(withTitle: self.local("打开 GitHub", "Open GitHub"))
            self.appState.prepareModalWindowPresentation()
            self.appState.configureModalWindow(alert.window)
            if alert.runModal() == .alertSecondButtonReturn,
               let url = URL(string: "https://github.com/f1ynng8/ClashMenu/")
            {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    private func appVersionString() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where shortVersion != buildVersion:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _):
            return shortVersion
        case let (_, buildVersion?):
            return buildVersion
        default:
            return "-"
        }
    }

    @objc
    private func quitApp(_ sender: Any?) {
        Task { @MainActor [weak self] in
            await self?.appState.quitApp()
        }
    }
}
