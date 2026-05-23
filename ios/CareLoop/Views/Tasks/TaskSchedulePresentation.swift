import Foundation

struct TaskSchedulePresentation {
    let repeats: Bool

    var scheduleSectionTitle: String {
        repeats ? "Schedule" : "Due date"
    }

    var dateToggleTitle: String {
        "Set due date"
    }

    var datePickerTitle: String {
        repeats ? "First occurrence" : "Due"
    }

    var scheduleHelperText: String {
        if repeats {
            return "Choose when the first task should happen. CareLoop uses that first occurrence to create the repeating series."
        }
        return "Optional for one-time tasks. Add a due date only when this task needs timing and reminders."
    }

    var recurrenceSectionTitle: String {
        repeats ? "Repeat rule" : "Recurrence"
    }

    var recurrenceHelperText: String {
        "CareLoop will create the next occurrence automatically after each completed recurring task."
    }
}
