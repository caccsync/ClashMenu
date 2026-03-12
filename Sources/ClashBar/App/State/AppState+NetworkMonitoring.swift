import AppKit
import Foundation

final class SystemSleepWakeObserver: NSObject {
    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(self.handleWillSleepNotification(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil)
        notificationCenter.addObserver(
            self,
            selector: #selector(self.handleDidWakeNotification(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func handleWillSleepNotification(_ notification: Notification) {
        Task { @MainActor [weak appState] in
            appState?.handleSystemWillSleep()
        }
    }

    @objc
    private func handleDidWakeNotification(_ notification: Notification) {
        Task { @MainActor [weak appState] in
            appState?.handleSystemDidWake()
        }
    }
}

@MainActor
extension AppState {
    func enforceNetworkManagedCorePolicyIfNeeded() {
        guard self.autoStopCoreOnNetworkDisconnectEnabled else { return }
        guard !self.isNetworkAutomationSuppressed else { return }

        switch self.networkReachabilityStatus {
        case .offline:
            self.scheduleAutoStopForNetworkLossIfNeeded()
        case .online:
            self.scheduleAutoStartForNetworkRecoveryIfNeeded()
        case .unknown:
            break
        }
    }

    func updateNetworkReachabilityMonitoringState() {
        if self.autoStopCoreOnNetworkDisconnectEnabled || self.autoStopCoreOnSystemSleepEnabled {
            self.startNetworkReachabilityMonitoringIfNeeded()
            self.enforceNetworkManagedCorePolicyIfNeeded()
        } else {
            self.stopNetworkReachabilityMonitoring(resetState: true)
        }
    }

    func configureSystemSleepWakeObservationIfNeeded() {
        guard self.systemSleepWakeObserver == nil else { return }
        self.systemSleepWakeObserver = SystemSleepWakeObserver(appState: self)
    }

    private var isNetworkAutomationSuppressed: Bool {
        if self.isSystemSleeping {
            return true
        }
        if let suppressedUntil = self.networkReachabilitySuppressedUntil {
            return suppressedUntil > Date()
        }
        return false
    }

    private func startNetworkReachabilityMonitoringIfNeeded() {
        guard !self.isNetworkReachabilityMonitoring else { return }
        self.isNetworkReachabilityMonitoring = true

        self.networkReachabilityMonitor.start { [weak self] status in
            Task { @MainActor in
                self?.handleNetworkReachabilityStatus(status)
            }
        }
    }

    func stopNetworkReachabilityMonitoring(resetState: Bool) {
        self.cancelNetworkAutomationTasks(resetRecoveryIntent: resetState)

        if self.isNetworkReachabilityMonitoring {
            self.networkReachabilityMonitor.stop()
            self.isNetworkReachabilityMonitoring = false
        }

        if resetState {
            self.networkReachabilityStatus = .unknown
            self.networkReachabilitySuppressedUntil = nil
            self.isSystemSleeping = false
            self.resolveRuntimeStopReason(.networkLoss)
            self.resolveRuntimeStopReason(.systemSleep)
        }
    }

    private func handleNetworkReachabilityStatus(_ status: NetworkReachabilityStatus) {
        let previous = self.networkReachabilityStatus
        self.networkReachabilityStatus = status

        guard self.autoStopCoreOnNetworkDisconnectEnabled else { return }
        guard previous != status else { return }
        guard !self.isNetworkAutomationSuppressed else { return }

        switch status {
        case .unknown:
            break
        case .offline:
            self.scheduleAutoStopForNetworkLossIfNeeded()
        case .online:
            self.scheduleAutoStartForNetworkRecoveryIfNeeded()
        }
    }

    fileprivate func handleSystemWillSleep() {
        guard self.autoStopCoreOnSystemSleepEnabled else { return }
        guard !self.isSystemSleeping else { return }

        self.isSystemSleeping = true
        self.networkReachabilitySuppressedUntil = nil
        self.cancelNetworkAutomationTasks(resetRecoveryIntent: false)
        self.appendLog(level: "info", message: "系统进入休眠，已暂停网络变化自动管理。")

        guard self.isRuntimeRunning else {
            self.runtimeStopReasons.insert(.systemSleep)
            return
        }

        self.registerManagedCoreStop(reason: .systemSleep)
        self.networkWakeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitUntilCoreActionIdleIfNeeded() else { return }
            guard self.isSystemSleeping else { return }
            guard self.isRuntimeRunning else { return }

            self.appendLog(level: "info", message: "系统休眠中，正在停止内核。")
            await self.stopCore(trigger: .systemSleep)
        }
    }

    fileprivate func handleSystemDidWake() {
        guard self.autoStopCoreOnSystemSleepEnabled else { return }

        self.isSystemSleeping = false
        self.cancelNetworkAutomationTasks(resetRecoveryIntent: false)
        self.networkReachabilitySuppressedUntil = Date().addingTimeInterval(
            TimeInterval(self.recoveryCheckDelaySeconds))
        self.appendLog(level: "info", message: "系统已唤醒，正在等待网络状态稳定后再执行自动管理。")

        self.networkWakeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.recoveryCheckDelayNanoseconds)
            } catch {
                return
            }

            guard self.autoStopCoreOnSystemSleepEnabled else { return }
            guard !self.isSystemSleeping else { return }

            self.networkReachabilitySuppressedUntil = nil
            self.resolveRuntimeStopReason(.systemSleep)
            if self.networkReachabilityStatus == .online, self.canAutoResumeManagedRuntime, !self.isRuntimeRunning {
                self.appendLog(level: "info", message: "系统唤醒恢复：正在重新启动内核。")
                await self.startCore(trigger: .systemWakeRecovery)
                if !self.isRuntimeRunning {
                    self.runtimeStopReasons.insert(.systemSleep)
                }
                return
            }
            self.enforceNetworkManagedCorePolicyIfNeeded()
        }
    }

    private func cancelNetworkAutomationTasks(resetRecoveryIntent: Bool) {
        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = nil
        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = nil
        self.networkWakeRecoveryTask?.cancel()
        self.networkWakeRecoveryTask = nil

        if resetRecoveryIntent {
            self.shouldAutoResumeManagedRuntime = false
        }
    }

    private func waitUntilCoreActionIdleIfNeeded() async -> Bool {
        for _ in 0..<40 {
            if Task.isCancelled { return false }
            guard self.autoStopCoreOnNetworkDisconnectEnabled || self.autoStopCoreOnSystemSleepEnabled else { return false }
            if !self.isCoreActionProcessing {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return false
            }
        }
        return !self.isCoreActionProcessing
    }

    private func scheduleAutoStopForNetworkLossIfNeeded() {
        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = nil

        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: self.networkOfflineStopDebounceNanoseconds)
            } catch {
                return
            }

            guard self.autoStopCoreOnNetworkDisconnectEnabled else { return }
            guard !self.isNetworkAutomationSuppressed else { return }
            guard self.networkReachabilityStatus == .offline else { return }
            guard self.isRuntimeRunning else { return }
            guard await self.waitUntilCoreActionIdleIfNeeded() else { return }
            guard self.networkReachabilityStatus == .offline else { return }
            guard self.isRuntimeRunning else { return }

            self.registerManagedCoreStop(reason: .networkLoss)
            self.appendLog(level: "warning", message: self.tr("log.network.offline_auto_stop"))
            await self.stopCore(trigger: .networkLoss)
        }
    }

    private func scheduleAutoStartForNetworkRecoveryIfNeeded() {
        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = nil

        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: self.recoveryCheckDelayNanoseconds)
            } catch {
                return
            }

            guard self.autoStopCoreOnNetworkDisconnectEnabled else { return }
            guard !self.isNetworkAutomationSuppressed else { return }
            guard self.networkReachabilityStatus == .online else { return }
            guard self.shouldAutoResumeManagedRuntime else { return }
            guard await self.waitUntilCoreActionIdleIfNeeded() else { return }
            guard self.networkReachabilityStatus == .online else { return }
            self.resolveRuntimeStopReason(.networkLoss)

            if self.isRuntimeRunning {
                if self.pendingCoreFeatureRecoveryState?.shouldRecoverAnyFeature == true {
                    await self.restoreCoreFeaturesAfterStartupIfNeeded()
                }
                self.shouldAutoResumeManagedRuntime = false
                return
            }

            guard self.canAutoResumeManagedRuntime else { return }
            self.appendLog(level: "info", message: self.tr("log.network.online_auto_start"))
            await self.startCore(trigger: .networkRecovery)
            if !self.isRuntimeRunning {
                self.runtimeStopReasons.insert(.networkLoss)
            }
        }
    }
}
