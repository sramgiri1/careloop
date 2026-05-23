import SwiftUI

struct TaskWeekdayPicker: View {
    @Binding var selection: Set<TaskWeekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TaskWeekday.allCases) { weekday in
                let isSelected = selection.contains(weekday)
                Button {
                    if isSelected {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(weekday.pillLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color(red: 0.13, green: 0.56, blue: 0.87) : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color(red: 0.88, green: 0.95, blue: 1.0) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isSelected ? Color(red: 0.13, green: 0.56, blue: 0.87) : Color(red: 0.84, green: 0.89, blue: 0.95),
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.fullLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
