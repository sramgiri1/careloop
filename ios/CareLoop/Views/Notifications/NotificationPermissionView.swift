import SwiftUI
import UserNotifications
import UIKit

struct NotificationPermissionView: View {
    let onResult: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text("Turn on reminders")
                    .font(.largeTitle.bold())
                Text("CareLoop can alert you before a task is due, when it is overdue, and when a family member assigns work to you.")
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    requestPermission()
                } label: {
                    HStack {
                        Spacer()
                        Text(requesting ? "Requesting..." : "Turn on reminders")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(requesting)
            }
            .padding(24)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
        .careLoopBrandBanner()
    }

    private func requestPermission() {
        requesting = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                requesting = false
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                onResult(granted)
                dismiss()
            }
        }
    }
}
