import BackgroundTasks
import FirebaseCore
import FirebaseInstallations
import FirebaseMessaging
import UIKit
import UserNotifications

final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Register the background refresh task that keeps the Live Activity current
        // while the app is suspended. iOS calls this at most every ~15 minutes.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.chocks.bgrefresh",
            using: nil
        ) { task in
            let refreshTask = Task { @MainActor in
                if LiveActivityManager.shared.isRunning {
                    await AircraftDataStore.shared?.refresh()
                }
                task.setTaskCompleted(success: !Task.isCancelled)
                AppDelegate.scheduleBackgroundRefresh()
            }
            task.expirationHandler = {
                refreshTask.cancel()
            }
        }
        AppDelegate.scheduleBackgroundRefresh()

        // Don't request permission here — onboarding handles the first-launch dialog.
        // On subsequent launches, if permission was already granted, re-register so
        // APNs refreshes the device token (required for Firebase Cloud Messaging).
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
                          || settings.authorizationStatus == .provisional
            guard authorized else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if DEBUG
        print("[AppDelegate] APNs device token received (\(deviceToken.count) bytes)")
        #endif
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[AppDelegate] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        print("[AppDelegate] FCM registration token: \(fcmToken ?? "nil")")
        Task {
            do {
                let fid = try await Installations.installations().installationID()
                print("[AppDelegate] Firebase installation ID (FID): \(fid)")
            } catch {
                print("[AppDelegate] Could not read Firebase installation ID: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
    }

    // MARK: - Background refresh scheduling

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.chocks.bgrefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[AppDelegate] Failed to schedule background refresh: \(error.localizedDescription)")
            #endif
        }
    }
}
