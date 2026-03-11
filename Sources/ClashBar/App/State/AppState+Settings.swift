import Foundation

@MainActor
extension AppState {
    func applySettingTunMode(_ value: Bool) async {
        await toggleTunMode(value)
    }

    func syncEditableSettings(from config: ConfigSnapshot) {
        let incoming = EditableSettingsSnapshot(config: config)

        if preserveLocalSettingsOnNextSync {
            preserveLocalSettingsOnNextSync = false
            lastSyncedEditableSettings = incoming
            persistEditableSettingsSnapshot()
            return
        }

        guard let previous = lastSyncedEditableSettings else {
            self.applyEditableSettingsSnapshotToUI(incoming)
            lastSyncedEditableSettings = incoming
            persistEditableSettingsSnapshot()
            return
        }

        suppressSettingsPersistence = true
        self.syncEditableFields(
            from: previous,
            to: incoming,
            fields: [
                (\.isTunEnabled, \.tunEnabled),
            ])
        suppressSettingsPersistence = false

        lastSyncedEditableSettings = incoming
        persistEditableSettingsSnapshot()
    }

    func currentEditableSettingsSnapshot() -> EditableSettingsSnapshot {
        EditableSettingsSnapshot(tunEnabled: desiredTunEnabled)
    }

    func applyPendingConfigSwitchSettingsOverlayIfNeeded() async {
        guard let overlay = pendingConfigSwitchOverlaySettings else { return }
        pendingConfigSwitchOverlaySettings = nil
        _ = await self.applyEditableSettingsOverlay(
            overlay,
            syncingKey: "config-switch-overlay",
            successMessage: tr("app.settings.overlay_success"))
    }

    func applyPendingAppLaunchSettingsOverlayIfNeeded() async {
        guard let overlay = pendingAppLaunchOverlaySettings else { return }
        guard apiStatus == .healthy else { return }
        pendingAppLaunchOverlaySettings = nil
        _ = await self.applyEditableSettingsOverlay(
            overlay,
            syncingKey: "app-launch-overlay",
            successMessage: "")
    }

    func syncEditableSettingsOverlayForCoreBootstrap(
        _ overlay: EditableSettingsSnapshot,
        syncingKey: String) async
    {
        self.deferredEditableSettingsOverlay = (snapshot: overlay, syncingKey: syncingKey)

        if await self.applyDeferredEditableSettingsOverlayIfPossible() {
            self.deferredEditableSettingsOverlayTask?.cancel()
            self.deferredEditableSettingsOverlayTask = nil
            return
        }

        self.scheduleDeferredEditableSettingsOverlaySync()
    }

    func cancelDeferredEditableSettingsOverlaySync() {
        self.deferredEditableSettingsOverlayTask?.cancel()
        self.deferredEditableSettingsOverlayTask = nil
        self.deferredEditableSettingsOverlay = nil
    }

    @discardableResult
    func applyEditableSettingsOverlay(
        _ overlay: EditableSettingsSnapshot,
        syncingKey: String,
        successMessage: String) async -> Bool
    {
        var body: [String: ConfigPatchValue] = [:]
        let tunBody = await self.tunOverlayPatchBody(enabled: overlay.tunEnabled)
        body["tun"] = .object(tunBody)
        if overlay.tunEnabled {
            body["dns"] = .object(["enable": .bool(true)])
        }

        return await self.patchConfigBody(body, syncingKey: syncingKey, successMessage: successMessage)
    }

    func applyEditableSettingsSnapshotToUI(_ snapshot: EditableSettingsSnapshot) {
        suppressSettingsPersistence = true
        desiredTunEnabled = snapshot.tunEnabled
        isTunEnabled = snapshot.tunEnabled
        suppressSettingsPersistence = false
    }

    @discardableResult
    func patchConfigBody(_ body: [String: ConfigPatchValue], syncingKey: String, successMessage: String) async -> Bool {
        settingsFeedbackClearTask?.cancel()
        settingsFeedbackClearTask = nil
        settingsSyncingKey = syncingKey
        settingsErrorMessage = nil
        settingsSavedMessage = nil
        defer { settingsSyncingKey = nil }

        do {
            ensureAPIClient()
            let payload = body.mapValues(\.jsonValue)
            try await self.settingsPatchTransport().requestNoResponse(.patchConfigs(body: payload))
            settingsSavedMessage = successMessage
            self.scheduleSettingsFeedbackAutoClearIfNeeded(message: successMessage)
            await refreshFromAPI(includeSlowCalls: false)
            return true
        } catch {
            let message = tr("app.settings.error.save_failed", syncingKey, error.localizedDescription)
            if self.isOverlaySyncingKey(syncingKey) {
                appendLog(level: "error", message: message)
            } else {
                settingsErrorMessage = message
            }
            settingsSavedMessage = nil
            await refreshFromAPI(includeSlowCalls: false)
            return false
        }
    }

    private func isOverlaySyncingKey(_ syncingKey: String) -> Bool {
        syncingKey.hasSuffix("-overlay")
    }

    private func scheduleDeferredEditableSettingsOverlaySync() {
        self.deferredEditableSettingsOverlayTask?.cancel()
        self.deferredEditableSettingsOverlayTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<120 {
                if Task.isCancelled { return }
                guard self.isRuntimeRunning else { return }
                if await self.applyDeferredEditableSettingsOverlayIfPossible() {
                    self.deferredEditableSettingsOverlayTask = nil
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
            }

            self.deferredEditableSettingsOverlayTask = nil
        }
    }

    private func applyDeferredEditableSettingsOverlayIfPossible() async -> Bool {
        guard let deferred = self.deferredEditableSettingsOverlay else { return true }
        guard await self.isCoreAPIReachableForOverlaySync() else { return false }

        let applied = await self.applyEditableSettingsOverlay(
            deferred.snapshot,
            syncingKey: deferred.syncingKey,
            successMessage: "")
        if applied {
            self.deferredEditableSettingsOverlay = nil
        }
        return applied
    }

    private func isCoreAPIReachableForOverlaySync() async -> Bool {
        do {
            let client = try self.clientOrThrow()
            let _: VersionInfo = try await client.request(.version)
            return true
        } catch {
            return false
        }
    }

    func scheduleSettingsFeedbackAutoClearIfNeeded(message: String) {
        guard message.trimmedNonEmpty != nil else { return }

        settingsFeedbackClearTask?.cancel()
        settingsFeedbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }

            guard let self else { return }
            if self.settingsSavedMessage == message {
                self.settingsSavedMessage = nil
            }
        }
    }

    func clientOrThrow() throws -> MihomoAPIClient {
        if apiClient == nil {
            ensureAPIClient()
        }
        if let apiClient {
            return apiClient
        }
        throw APIError.invalidURL
    }

    func modeSwitchTransport() throws -> MihomoAPITransporting {
        try self.resolvedTransport(override: modeSwitchTransportOverride)
    }

    func settingsPatchTransport() throws -> MihomoAPITransporting {
        try self.resolvedTransport(override: settingsPatchTransportOverride)
    }

    private func tunOverlayPatchBody(enabled: Bool) async -> [String: ConfigPatchValue] {
        var tunBody: [String: ConfigPatchValue] = ["enable": .bool(enabled)]
        if enabled {
            let hasConfiguredStack = await self.selectedConfigDeclaresTunStack()
            if !hasConfiguredStack {
                tunBody["stack"] = .string("mixed")
            }
        }
        return tunBody
    }

    private func syncEditableFields<Value: Equatable>(
        from previous: EditableSettingsSnapshot,
        to incoming: EditableSettingsSnapshot,
        fields: [(ReferenceWritableKeyPath<AppState, Value>, KeyPath<EditableSettingsSnapshot, Value>)])
    {
        for (stateKeyPath, snapshotKeyPath) in fields {
            guard self[keyPath: stateKeyPath] == previous[keyPath: snapshotKeyPath] else { continue }
            self[keyPath: stateKeyPath] = incoming[keyPath: snapshotKeyPath]
        }
    }

    private func resolvedTransport(override: MihomoAPITransporting?) throws -> MihomoAPITransporting {
        if let override {
            return override
        }
        return try self.clientOrThrow()
    }
}
