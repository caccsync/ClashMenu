import AppKit
import Combine

@MainActor
final class NativeSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    private let launchAtLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoStartCoreButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoManageCoreButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let allowLanButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let ipv6Button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let tcpConcurrentButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let logLevelLabel = NSTextField(labelWithString: "")
    private let logLevelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let flushFakeIPButton = NSButton(title: "", target: nil, action: nil)
    private let flushDNSButton = NSButton(title: "", target: nil, action: nil)
    private let openCoreDirectoryButton = NSButton(title: "", target: nil, action: nil)

    private var observers: [AnyCancellable] = []
    private var selectedLanguageMap: [Int: AppLanguage] = [:]
    private var selectedLogLevelMap: [Int: ConfigLogLevel] = [:]

    init(appState: AppState) {
        self.appState = appState

        let contentRect = NSRect(x: 0, y: 0, width: 340, height: 420)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        self.configureWindow()
        self.buildContentView()
        self.bindState()
        self.refreshFromState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        self.appState.refreshLaunchAtLoginStatus()
        self.refreshFromState()
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        self.refreshFromState()
    }

    private func configureWindow() {
        guard let window else { return }
        window.delegate = self
        window.level = .statusBar
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.titleVisibility = .visible
    }

    private func buildContentView() {
        guard let window else { return }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView
        window.contentMinSize = NSSize(width: 340, height: 380)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        [
            self.launchAtLoginButton,
            self.autoStartCoreButton,
            self.autoManageCoreButton,
            self.allowLanButton,
            self.ipv6Button,
            self.tcpConcurrentButton,
        ].forEach { button in
            button.setButtonType(.switch)
            button.target = self
            stack.addArrangedSubview(button)
        }

        self.launchAtLoginButton.action = #selector(self.toggleLaunchAtLogin(_:))
        self.autoStartCoreButton.action = #selector(self.toggleAutoStartCore(_:))
        self.autoManageCoreButton.action = #selector(self.toggleAutoManageCore(_:))
        self.allowLanButton.action = #selector(self.toggleAllowLan(_:))
        self.ipv6Button.action = #selector(self.toggleIPv6(_:))
        self.tcpConcurrentButton.action = #selector(self.toggleTCPConcurrent(_:))

        let languageRow = self.makePopupRow(label: self.languageLabel, popup: self.languagePopup)
        let logLevelRow = self.makePopupRow(label: self.logLevelLabel, popup: self.logLevelPopup)
        stack.addArrangedSubview(languageRow)
        stack.addArrangedSubview(logLevelRow)

        self.languagePopup.target = self
        self.languagePopup.action = #selector(self.changeLanguage(_:))
        self.logLevelPopup.target = self
        self.logLevelPopup.action = #selector(self.changeLogLevel(_:))

        let divider = NSBox()
        divider.boxType = .separator
        stack.addArrangedSubview(divider)

        let actionsRow = NSStackView()
        actionsRow.orientation = .vertical
        actionsRow.spacing = 8
        self.flushFakeIPButton.bezelStyle = .rounded
        self.flushDNSButton.bezelStyle = .rounded
        self.openCoreDirectoryButton.bezelStyle = .rounded
        self.flushFakeIPButton.target = self
        self.flushDNSButton.target = self
        self.openCoreDirectoryButton.target = self
        self.flushFakeIPButton.action = #selector(self.flushFakeIP(_:))
        self.flushDNSButton.action = #selector(self.flushDNS(_:))
        self.openCoreDirectoryButton.action = #selector(self.openCoreDirectory(_:))
        actionsRow.addArrangedSubview(self.flushFakeIPButton)
        actionsRow.addArrangedSubview(self.flushDNSButton)
        actionsRow.addArrangedSubview(self.openCoreDirectoryButton)
        stack.addArrangedSubview(actionsRow)
    }

    private func makePopupRow(label: NSTextField, popup: NSPopUpButton) -> NSView {
        label.font = .systemFont(ofSize: 13, weight: .medium)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        popup.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true

        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        return row
    }

    private func bindState() {
        self.observers = [
            self.appState.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshFromState()
                }
            },
        ]
    }

    private func refreshFromState() {
        self.syncLocalizedText()
        self.launchAtLoginButton.state = self.appState.launchAtLoginEnabled ? .on : .off
        self.autoStartCoreButton.state = self.appState.autoStartCoreEnabled ? .on : .off
        self.autoManageCoreButton.state = self.appState.autoManageCoreOnNetworkChangeEnabled ? .on : .off
        self.allowLanButton.state = self.appState.settingsAllowLan ? .on : .off
        self.ipv6Button.state = self.appState.settingsIPv6 ? .on : .off
        self.tcpConcurrentButton.state = self.appState.settingsTCPConcurrent ? .on : .off

        for (tag, language) in self.selectedLanguageMap where language == self.appState.uiLanguage {
            self.languagePopup.selectItem(withTag: tag)
        }
        for (tag, level) in self.selectedLogLevelMap where level.rawValue == self.appState.settingsLogLevel {
            self.logLevelPopup.selectItem(withTag: tag)
        }
    }

    private func syncLocalizedText() {
        guard let window else { return }
        window.title = self.local("设置", "Settings")
        self.launchAtLoginButton.title = self.tr("ui.settings.launch_at_login")
        self.autoStartCoreButton.title = self.tr("ui.settings.auto_start_core")
        self.autoManageCoreButton.title = self.tr("ui.settings.auto_core_network_recovery")
        self.allowLanButton.title = self.tr("ui.settings.allow_lan")
        self.ipv6Button.title = self.tr("ui.settings.ipv6")
        self.tcpConcurrentButton.title = self.tr("ui.settings.tcp_concurrent")
        self.languageLabel.stringValue = self.tr("ui.settings.language")
        self.logLevelLabel.stringValue = self.tr("ui.settings.log_level")
        self.flushFakeIPButton.title = self.local("清理 FakeIP 缓存", "Clear FakeIP Cache")
        self.flushDNSButton.title = self.local("清理 DNS 缓存", "Clear DNS Cache")
        self.openCoreDirectoryButton.title = self.tr("ui.action.open_core_directory")

        self.languagePopup.removeAllItems()
        self.selectedLanguageMap.removeAll()
        for (index, language) in AppLanguage.allCases.enumerated() {
            let title = switch language {
            case .zhHans:
                self.local("简体中文", "Simplified Chinese")
            case .en:
                "English"
            }
            self.languagePopup.addItem(withTitle: title)
            self.languagePopup.lastItem?.tag = index
            self.selectedLanguageMap[index] = language
        }

        self.logLevelPopup.removeAllItems()
        self.selectedLogLevelMap.removeAll()
        for (index, level) in ConfigLogLevel.allCases.enumerated() {
            self.logLevelPopup.addItem(withTitle: level.rawValue)
            self.logLevelPopup.lastItem?.tag = index
            self.selectedLogLevelMap[index] = level
        }
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
    private func toggleLaunchAtLogin(_ sender: NSButton) {
        let enabled = sender.state == .on
        self.appState.applyLaunchAtLogin(enabled)
        if let message = self.appState.launchAtLoginErrorMessage {
            sender.state = self.appState.launchAtLoginEnabled ? .on : .off
            self.presentError(message)
        }
    }

    @objc
    private func toggleAutoStartCore(_ sender: NSButton) {
        self.appState.autoStartCoreEnabled = sender.state == .on
    }

    @objc
    private func toggleAutoManageCore(_ sender: NSButton) {
        self.appState.autoManageCoreOnNetworkChangeEnabled = sender.state == .on
    }

    @objc
    private func toggleAllowLan(_ sender: NSButton) {
        self.applyBooleanSetting(.allowLan, from: sender)
    }

    @objc
    private func toggleIPv6(_ sender: NSButton) {
        self.applyBooleanSetting(.ipv6, from: sender)
    }

    @objc
    private func toggleTCPConcurrent(_ sender: NSButton) {
        self.applyBooleanSetting(.tcpConcurrent, from: sender)
    }

    private func applyBooleanSetting(_ setting: AppState.EditableCoreSetting, from button: NSButton) {
        let enabled = button.state == .on
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appState.applyEditableCoreSetting(setting, to: enabled)
            if let message = self.appState.settingsErrorMessage {
                self.refreshFromState()
                self.presentError(message)
            }
        }
    }

    @objc
    private func changeLanguage(_ sender: NSPopUpButton) {
        guard let language = self.selectedLanguageMap[sender.selectedTag()] else { return }
        self.appState.setUILanguage(language)
        self.refreshFromState()
    }

    @objc
    private func changeLogLevel(_ sender: NSPopUpButton) {
        guard let level = self.selectedLogLevelMap[sender.selectedTag()] else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appState.applyEditableCoreSetting(.logLevel, to: level.rawValue)
            if let message = self.appState.settingsErrorMessage {
                self.refreshFromState()
                self.presentError(message)
            }
        }
    }

    @objc
    private func flushFakeIP(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message = await self.appState.runNoResponseAction(
                self.local("清理 FakeIP 缓存", "Clear FakeIP Cache"),
                operation: {
                    try await self.appState.clientOrThrow().requestNoResponse(.flushFakeIPCache)
                })
            {
                self.presentError(message)
            }
        }
    }

    @objc
    private func flushDNS(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message = await self.appState.runNoResponseAction(
                self.local("清理 DNS 缓存", "Clear DNS Cache"),
                operation: {
                    try await self.appState.clientOrThrow().requestNoResponse(.flushDNSCache)
                })
            {
                self.presentError(message)
            }
        }
    }

    @objc
    private func openCoreDirectory(_ sender: Any?) {
        self.appState.showCoreDirectoryInFinder()
    }
}
