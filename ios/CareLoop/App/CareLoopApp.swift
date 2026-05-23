import SwiftUI
import UIKit
import UserNotifications

#if DEBUG
private enum LaunchArguments {
    static let resetSession = "-careloop-ui-reset-session"
}
#endif

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .careLoopPushTokenRegistered, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let taskId = response.notification.request.content.userInfo["taskId"] as? String {
            var payload = ["taskId": taskId]
            if let circleId = response.notification.request.content.userInfo["circleId"] as? String {
                payload["circleId"] = circleId
            }
            if let recipientId = response.notification.request.content.userInfo["recipientId"] as? String {
                payload["recipientId"] = recipientId
            }
            NotificationCenter.default.post(name: .careLoopPushTaskOpened, object: payload)
        }
        completionHandler()
    }
}

@main
struct CareLoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.resetSession) {
            AppState.resetPersistedSession()
        }
        if let scenario = UITestScenario.current {
            _appState = StateObject(wrappedValue: AppState(uiTestScenario: scenario))
            return
        }
        if let launchSession = DemoLaunchSession.current {
            _appState = StateObject(wrappedValue: AppState(launchSession: launchSession))
            return
        }
        #endif
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            if appState.currentUser == nil {
                OnboardingView()
                    .environmentObject(appState)
            } else {
                ContentView()
                    .environmentObject(appState)
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active,
                  let user   = appState.currentUser,
                  let circle = appState.activeCircle
            else { return }
            Task { try? await APIClient.shared.logSession(userId: user.id, circleId: circle.id) }
        }
    }
}
