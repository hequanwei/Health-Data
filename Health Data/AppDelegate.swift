//
//  AppDelegate.swift
//  Health Data
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundScanScheduler.register()
        BackgroundScanScheduler.scheduleNextScan()
        return true
    }
}
