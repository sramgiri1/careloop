import Foundation

struct CircleCompletionInsights: Codable {
    let periodDays: Int
    let selectedRecipientId: String?
    let completedByDay: [CompletedTaskDay]
    let taskTrendByDay: [TaskTrendDay]
    let topCaregivers: [TopCaregiverInsight]
    let caregiverLoad: [CaregiverLoadInsight]
    let escalationSummary: EscalationInsightSummary
    let recipientBreakdown: [RecipientCompletionInsight]
    let adherence: AdherenceInsightSummary
    let totals: CompletionInsightTotals
}

struct RecipientCompletionInsight: Codable, Identifiable {
    let recipientId: String
    let name: String
    let completed: Int
    let active: Int
    let overdue: Int
    let adherence: AdherenceInsightSummary

    var id: String { recipientId }
}

struct AdherenceInsightSummary: Codable, Equatable {
    let scheduled: Int
    let completed: Int
    let onTime: Int
    let late: Int
    let missed: Int
    let completionRate: Int
    let onTimeRate: Int

    static let empty = AdherenceInsightSummary(
        scheduled: 0,
        completed: 0,
        onTime: 0,
        late: 0,
        missed: 0,
        completionRate: 0,
        onTimeRate: 0
    )

    var completionRateLabel: String {
        scheduled == 0 ? "No due tasks" : "\(completionRate)%"
    }

    var onTimeRateLabel: String {
        scheduled == 0 ? "No due tasks" : "\(onTimeRate)%"
    }

    var summaryLabel: String {
        if scheduled == 0 {
            return "No due tasks in this window yet."
        }
        return "\(completed) of \(scheduled) due tasks completed, \(onTime) on time."
    }
}

struct CompletedTaskDay: Codable, Identifiable {
    let date: String
    let count: Int

    var id: String { date }

    var shortLabel: String {
        Self.shortLabel(for: date)
    }

    static func shortLabel(for date: String) -> String {
        displayFormatter.string(from: sourceFormatter.date(from: date) ?? Date())
    }

    private static let sourceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

struct TaskTrendDay: Codable, Identifiable {
    let date: String
    let due: Int
    let completed: Int
    let missed: Int

    var id: String { date }

    var shortLabel: String {
        CompletedTaskDay.shortLabel(for: date)
    }

    var needsAttention: Bool {
        missed > 0
    }
}

struct TopCaregiverInsight: Codable, Identifiable {
    let userId: String
    let name: String
    let email: String
    let completedCount: Int

    var id: String { userId }
}

struct CaregiverLoadInsight: Codable, Identifiable {
    let userId: String
    let name: String
    let email: String
    let completedCount: Int
    let activeAssignedCount: Int
    let overdueAssignedCount: Int
    let totalAssignedCount: Int

    var id: String { userId }

    var loadSummaryLabel: String {
        "\(activeAssignedCount) active · \(overdueAssignedCount) overdue"
    }
}

struct EscalationInsightSummary: Codable, Equatable {
    let totalEscalated: Int
    let averageResponseMinutes: Int?
    let recent: [EscalationInsightItem]

    static let empty = EscalationInsightSummary(
        totalEscalated: 0,
        averageResponseMinutes: nil,
        recent: []
    )

    var totalLabel: String {
        totalEscalated == 1 ? "1 escalation" : "\(totalEscalated) escalations"
    }

    var averageResponseLabel: String {
        guard let averageResponseMinutes else {
            return "No response time yet"
        }
        return "\(averageResponseMinutes) min avg response"
    }
}

struct EscalationInsightItem: Codable, Identifiable, Equatable {
    let taskId: String
    let taskTitle: String
    let recipientId: String?
    let recipientName: String?
    let escalatedAt: Date
    let responseMinutes: Int?

    var id: String { "\(taskId)-\(escalatedAt.timeIntervalSince1970)" }

    var responseLabel: String {
        guard let responseMinutes else {
            return "Response time unavailable"
        }
        return "\(responseMinutes) min response"
    }
}

struct CompletionInsightTotals: Codable {
    let completed: Int
    let active: Int
    let overdue: Int
}
