import SwiftUI

struct JoinCircleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var dismissOnSuccess: Bool = false
    /// When non-nil, the mode picker is hidden and the view starts locked to this mode.
    /// true = create, false = join
    var startInCreateMode: Bool? = nil

    private enum Mode: String, CaseIterable {
        case join = "Join existing circle"
        case create = "Create new circle"
    }

    private enum InputField: Hashable {
        case circleId
        case circleName
        case recipientName
    }

    @State private var mode: Mode

    init(dismissOnSuccess: Bool = false, startInCreateMode: Bool? = nil) {
        self.dismissOnSuccess = dismissOnSuccess
        self.startInCreateMode = startInCreateMode
        _mode = State(initialValue: startInCreateMode == true ? .create : .join)
    }

    @State private var circleId      = ""
    @State private var circleName    = ""
    @State private var recipientName = ""
    @State private var loading       = false
    @State private var error:        String?
    @FocusState private var focusedField: InputField?

    private var reachedCircleLimit: Bool {
        (appState.currentUser?.memberships?.count ?? 0) >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    CareLoopBrandView(style: .wordmark, surface: .light, wordmarkHeight: 36)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    header
                    if startInCreateMode == nil {
                        modePicker
                    }
                    formCard

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if reachedCircleLimit {
                        Text("You can belong to up to 3 circles. Leave or remove a circle before joining or creating another.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == .join ? "Join circle" : "Create circle")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(mode == .join ? "join-circle-submit-button" : "create-circle-submit-button")
                    .disabled(loading || !isValid || reachedCircleLimit)
                    .opacity(loading || !isValid || reachedCircleLimit ? 0.55 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.99).ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up your CareLoop")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.16, blue: 0.24))
            let subtitle: String = {
                if startInCreateMode == true {
                    return "Create your Care Circle, then invite the first care receiver so care starts with consent."
                } else if startInCreateMode == false {
                    return "Enter the invite code or circle ID shared with you by your family."
                }
                return "Join a circle you were invited to, or create a new one to organize care, tasks, and updates for your family."
            }()
            Text(subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.60))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ForEach(Mode.allCases, id: \.self) { candidate in
                Button {
                    mode = candidate
                    error = nil
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(mode == candidate ? .white : Color(red: 0.23, green: 0.33, blue: 0.44))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Group {
                                if mode == candidate {
                                    LinearGradient(
                                        colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    Color.white
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color(red: 0.84, green: 0.89, blue: 0.95), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if mode == .join {
                Text("Join an existing circle")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Enter the circle ID shared by the circle admin.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                field("Circle ID", text: $circleId, placeholder: "circle-123", field: .circleId)
            } else {
                Text("Create a new circle")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Add the first care receiver now. Tasks unlock after they accept the invite or are proxy-activated.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                field("Circle name", text: $circleName, placeholder: "Smith Family Care", field: .circleName)
                field("Who is being cared for?", text: $recipientName, placeholder: "e.g. Mom, Dad, John", field: .recipientName)
            }
        }
        .padding(22)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var isValid: Bool {
        switch mode {
        case .join:
            return OnboardingValidation.joinCircle(circleId: circleId)
        case .create:
            return OnboardingValidation.createCircle(circleName: circleName)
                && !recipientName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func submit() {
        guard appState.currentUser != nil else { return }
        loading = true
        error = nil

        Task {
            defer { loading = false }
            do {
                switch mode {
                case .join:
                    let trimmedCircleId = circleId.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        _ = try await APIClient.shared.addMember(circleId: trimmedCircleId)
                    } catch APIError.httpError(let statusCode, _) where statusCode == 409 {
                        // Treat duplicate join as success so users can re-enter an existing circle.
                    }
                    try await appState.activateCircle(id: trimmedCircleId)
                    if dismissOnSuccess {
                        dismiss()
                    }
                case .create:
                    let created = try await APIClient.shared.createCircle(
                        name: circleName.trimmingCharacters(in: .whitespacesAndNewlines),
                        recipientName: recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    try await appState.activateCircle(id: created.id, promptNewTask: false)
                    if dismissOnSuccess {
                        dismiss()
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, field: InputField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(title == "Circle ID" ? .never : .words)
                .autocorrectionDisabled()
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(Color(red: 0.97, green: 0.98, blue: 0.99))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(red: 0.86, green: 0.90, blue: 0.95), lineWidth: 1.5)
                )
                .focused($focusedField, equals: field)
                .submitLabel(field == .circleName ? .next : .done)
                .onSubmit {
                    switch field {
                    case .circleName:
                        focusedField = .recipientName
                    default:
                        focusedField = nil
                    }
                }
                .accessibilityIdentifier(fieldIdentifier(for: title))
        }
    }

    private func fieldIdentifier(for title: String) -> String {
        switch title {
        case "Circle ID":
            return "join-circle-id-field"
        case "Circle name":
            return "create-circle-name-field"
        case "Who is being cared for?":
            return "create-circle-recipient-field"
        default:
            return "join-circle-field-\(title)"
        }
    }
}
