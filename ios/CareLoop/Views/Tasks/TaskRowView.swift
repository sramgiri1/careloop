import SwiftUI

struct TaskRowView: View {
    let task:     CareTask
    let onToggle: () -> Void

    private var isDone: Bool { task.status == .done || task.status == .skipped }

    // MARK: – Design tokens
    private let teal  = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue  = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let dark  = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid   = Color(red: 0.43, green: 0.50, blue: 0.60)

    var body: some View {
        HStack(spacing: 0) {
            priorityBar
            rowContent
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isDone ? 0.02 : 0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: – Left priority bar

    private var priorityBar: some View {
        Rectangle()
            .fill(priorityBarColor)
            .frame(width: 4)
            .clipShape(.rect(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            ))
    }

    private var priorityBarColor: Color {
        guard !isDone else { return .clear }
        switch task.priority {
        case .urgent: return .red
        case .high:   return .orange
        default:      return .clear
        }
    }

    // MARK: – Row content

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            checkboxButton
            centerContent
            Spacer(minLength: 4)
            rightAccessory
        }
        .padding(.vertical, 13)
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }

    // MARK: – Checkbox

    private var checkboxButton: some View {
        Button(action: onToggle) {
            Image(systemName: checkboxIcon)
                .font(.system(size: 24))
                .foregroundStyle(checkboxColor)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(!task.canToggleCompletion)
        .opacity(task.canToggleCompletion ? 1 : 0.45)
        .padding(.top, 1)
        .accessibilityIdentifier("task-toggle-\(task.id)")
    }

    private var checkboxIcon: String {
        switch task.status {
        case .done:       return "checkmark.circle.fill"
        case .skipped:    return "forward.circle.fill"
        case .inProgress: return "circle.dotted"
        case .pending:    return task.isOverdue ? "exclamationmark.circle" : "circle"
        }
    }

    private var checkboxColor: Color {
        switch task.status {
        case .done:       return Color(red: 0.12, green: 0.68, blue: 0.49)
        case .skipped:    return .orange
        case .inProgress: return blue
        case .pending:    return task.isOverdue ? .red : Color(uiColor: .tertiaryLabel)
        }
    }

    // MARK: – Center content

    private var centerContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isDone ? mid : dark)
                .strikethrough(task.status == .done, color: mid)
                .lineLimit(2)

            metaRow
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let name = task.recipient?.name {
                metaChip(name, icon: "person.fill", color: blue)
            }
            if task.status == .done, let doer = task.completedBy?.name {
                let first = doer.split(separator: " ").first.map(String.init) ?? doer
                metaChip("Done by \(first)", icon: "checkmark.circle.fill",
                         color: Color(red: 0.12, green: 0.68, blue: 0.49))
            } else if isDone {
                metaChip("Done", icon: "checkmark.circle.fill",
                         color: Color(red: 0.12, green: 0.68, blue: 0.49))
            } else {
                if let due = task.dueAt {
                    metaChip(dueLabel(due), icon: "clock", color: task.isOverdue ? .red : mid)
                }
                if let assignee = task.assignee?.name {
                    let first = assignee.split(separator: " ").first.map(String.init) ?? assignee
                    metaChip(first, icon: "person.circle", color: mid)
                }
            }
            if task.recurrence != nil {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(mid.opacity(0.7))
            }
        }
    }

    private func metaChip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .lineLimit(1)
    }

    private func dueLabel(_ date: Date) -> String {
        if date < Date() { return "Overdue" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: – Right accessory

    @ViewBuilder
    private var rightAccessory: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if task.priority == .urgent {
                priorityBadge("URGENT", color: .red)
            } else if task.priority == .high {
                priorityBadge("HIGH", color: .orange)
            }
        }
        .padding(.top, 2)
    }

    private func priorityBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}
