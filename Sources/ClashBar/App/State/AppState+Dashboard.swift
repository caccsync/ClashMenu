import Foundation

@MainActor
extension AppState {
    func seedBundledDashboardIfNeeded() {
        let fileManager = FileManager.default

        guard let bundledDashboardURL = self.bundledDashboardURL(fileManager: fileManager) else {
            return
        }

        let targetURL = self.workingDirectoryManager.uiDirectoryURL.appendingPathComponent("zashboard", isDirectory: true)

        do {
            try self.workingDirectoryManager.bootstrapDirectories(fileManager: fileManager)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: bundledDashboardURL, to: targetURL)
        } catch {
            self.appendLog(level: "error", message: "Failed to prepare bundled zashboard: \(error.localizedDescription)")
        }
    }

    private func bundledDashboardURL(fileManager: FileManager = .default) -> URL? {
        let candidateRelativePaths = [
            "zashboard",
            "Resources/zashboard",
        ]

        for root in AppResourceBundleLocator.candidateResourceRoots() {
            for relativePath in candidateRelativePaths {
                let candidate = root.appendingPathComponent(relativePath, isDirectory: true)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let indexURL = candidate.appendingPathComponent("index.html", isDirectory: false)
                    if fileManager.fileExists(atPath: indexURL.path) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }
}
