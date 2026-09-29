//
//  BackgroundScanScheduler.swift
//  Health Data
//

import BackgroundTasks
import Foundation

enum BackgroundScanScheduler {
    static let taskIdentifier = "com.personal.Health-Data.daily-scan"
    private static let minimumInterval: TimeInterval = 60 * 60 * 12

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppRefresh(task: refreshTask)
        }
    }

    static func scheduleNextScan() {
        guard HealthAlertSettings.isBackgroundScanEnabled else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextScan()

        let operation = Task { @MainActor in
            let success = await HealthManager().performBackgroundScan()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
}
