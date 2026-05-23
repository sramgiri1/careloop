import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var socialAuth = SocialAuthSession()

    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var showSignInPassword = false

    @State private var createName = ""
    @State private var createEmail = ""
    @State private var createPassword = ""
    @State private var createConfirmPassword = ""
    @State private var createAcceptedTerms = false
    @State private var showCreatePassword = false
    @State private var showCreateConfirmPassword = false
    @State private var selectedProvider: AuthProvider = .email

    @State private var forgotEmail = ""
    @State private var forgotCode = ""
    @State private var forgotDebugCode: String?
    @State private var forgotNewPassword = ""
    @State private var forgotConfirmPassword = ""
    @State private var forgotResendSeconds = 8
    @State private var showForgotNewPassword = false
    @State private var showForgotConfirmPassword = false

    @State private var error: String?
    @State private var loading = false
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @State private var forgotStep: ForgotPasswordStep = .email

    private let pageBackground = Color(red: 0.96, green: 0.97, blue: 0.99)
    private let inputBorder = Color(red: 0.84, green: 0.89, blue: 0.94)
    private let secondaryText = Color(red: 0.61, green: 0.69, blue: 0.77)
    private let accent = Color(red: 0.11, green: 0.76, blue: 0.72)
    private let accent2 = Color(red: 0.10, green: 0.53, blue: 0.83)
    private let caution = Color(red: 0.99, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    loginHero

                    VStack(spacing: 0) {
                        signInFields
                        forgotPasswordLink
                        loginButton
                        continueDivider("or continue with")
                        socialRow

                        if let error {
                            authError(error)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 26)
                }

                Spacer(minLength: 0)
                loginFooter
            }
            .background(pageBackground.ignoresSafeArea())
            .fullScreenCover(isPresented: $showSignUp) {
                signUpFlow
            }
            .fullScreenCover(isPresented: $showForgotPassword) {
                forgotPasswordFlow
            }
        }
    }

    private var loginHero: some View {
        authHero(
            title: "Welcome back",
            subtitle: "Continue your care journey",
            showsBackButton: false
        ) {
            EmptyView()
        }
    }

    private var signInFields: some View {
        VStack(spacing: 18) {
            authTextField("Email address", text: $signInEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            authSecureField("Password", text: $signInPassword, isVisible: $showSignInPassword)
        }
    }

    private var forgotPasswordLink: some View {
        HStack {
            Spacer()
            Button("Forgot password?") {
                error = nil
                forgotEmail = signInEmail
                forgotCode = ""
                forgotDebugCode = nil
                forgotNewPassword = ""
                forgotConfirmPassword = ""
                forgotStep = .email
                forgotResendSeconds = 8
                showForgotPassword = true
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var loginButton: some View {
        gradientActionButton(title: "Log in", disabled: loading || !canSignIn, loading: loading) {
            submitSignInTapped()
        }
    }

    private var socialRow: some View {
        HStack(spacing: 14) {
            socialButton(.google)
            socialButton(.facebook)
            socialButton(.apple)
        }
    }

    private var loginFooter: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(secondaryText)
            Button("Sign up") {
                resetSignUpState()
                showSignUp = true
            }
            .foregroundStyle(accent)
            .fontWeight(.bold)
        }
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(pageBackground)
    }

    private var signUpFlow: some View {
        VStack(spacing: 0) {
            authHero(
                title: "Create your account",
                subtitle: "Join thousands on their care journey",
                showsBackButton: true,
                heroHeight: 252
            ) {
                EmptyView()
            } onBack: {
                showSignUp = false
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    authProviderCard(.google)
                    authProviderCard(.facebook)
                    authProviderCard(.apple)
                }

                continueDivider("or with email")
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                VStack(spacing: 12) {
                    authTextField("Full name", text: $createName)
                    authTextField("Email address", text: $createEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    authSecureField("Password", text: $createPassword, isVisible: $showCreatePassword)
                    authSecureField("Confirm password", text: $createConfirmPassword, isVisible: $showCreateConfirmPassword)
                }

                termsRow
                    .padding(.top, 14)

                if let error {
                    authError(error)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity)
                }

                gradientActionButton(title: "Create account", disabled: loading || !canCreate, loading: loading) {
                    submitCreateTapped()
                }
                .padding(.top, 16)

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(secondaryText)
                    Button("Log in") {
                        showSignUp = false
                    }
                    .foregroundStyle(accent)
                    .fontWeight(.bold)
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private var forgotPasswordFlow: some View {
        VStack(spacing: 0) {
            forgotHero

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch forgotStep {
                    case .email:
                        forgotEmailStep
                    case .verify:
                        forgotVerifyStep
                    case .reset:
                        forgotResetStep
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .onAppear {
            if forgotStep == .verify {
                startResendCountdown()
            }
        }
    }

    private var forgotHero: some View {
        authHero(
            title: forgotStep.title,
            subtitle: forgotStep.subtitle(email: forgotEmail),
            showsBackButton: true,
            heroHeight: 326
        ) {
            forgotProgress
        } onBack: {
            switch forgotStep {
            case .email:
                showForgotPassword = false
            case .verify:
                forgotStep = .email
            case .reset:
                forgotStep = .verify
            }
        }
    }

    private var forgotProgress: some View {
        HStack(spacing: 0) {
            progressNode(index: 1, title: "Email", state: forgotStep.progressState(for: 1))
            progressLine(active: forgotStep.rawValue > 1)
            progressNode(index: 2, title: "Verify", state: forgotStep.progressState(for: 2))
            progressLine(active: forgotStep.rawValue > 2)
            progressNode(index: 3, title: "Reset", state: forgotStep.progressState(for: 3))
        }
    }

    private var forgotEmailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoCard(
                systemImage: "envelope",
                text: "Enter the email address linked to your CareLoop account."
            )

            authTextField("Email address", text: $forgotEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.top, 20)

            if let error {
                authError(error)
                    .padding(.top, 14)
            }

            gradientActionButton(title: "Send code", disabled: loading || !OnboardingValidation.recoveryEmail(email: forgotEmail), loading: loading) {
                submitForgotEmail()
            }
            .padding(.top, 18)

            HStack(spacing: 4) {
                Text("Remembered it?")
                    .foregroundStyle(secondaryText)
                Button("Log in") {
                    showForgotPassword = false
                }
                .foregroundStyle(accent)
                .fontWeight(.bold)
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        }
    }

    private var forgotVerifyStep: some View {
        VStack(spacing: 0) {
            Text("Enter the 6-digit code we sent you")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.35, blue: 0.46))
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            codeEntry
                .padding(.top, 28)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(inputBorder.opacity(0.7))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                Text("Resend code in")
                    .foregroundStyle(secondaryText)
                Text("\(forgotResendSeconds)s")
                    .foregroundStyle(Color(red: 0.26, green: 0.35, blue: 0.46))
                    .fontWeight(.bold)
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.top, 18)
            .frame(maxWidth: .infinity)

            warningCard
                .padding(.top, 24)

            if let error {
                authError(error)
                    .padding(.top, 14)
            }

            gradientActionButton(title: "Verify code", disabled: loading || forgotCode.count != 6, loading: loading) {
                submitForgotVerify()
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
    }

    private var forgotResetStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 16) {
                authSecureField("New password", text: $forgotNewPassword, isVisible: $showForgotNewPassword)
                authSecureField("Confirm new password", text: $forgotConfirmPassword, isVisible: $showForgotConfirmPassword)
            }
            .padding(.top, 16)

            if let error {
                authError(error)
                    .padding(.top, 14)
            }

            gradientActionButton(title: "Update password", disabled: loading || !OnboardingValidation.resetPassword(password: forgotNewPassword, confirmPassword: forgotConfirmPassword), loading: loading) {
                submitForgotReset()
            }
            .padding(.top, 22)
        }
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(caution)
                .font(.system(size: 18, weight: .semibold))

            (
                Text("This code expires in ")
                + Text("10 minutes").bold()
                + Text(". Never share it with anyone.")
            )
            .foregroundColor(Color(red: 0.60, green: 0.41, blue: 0.02))
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color(red: 1.0, green: 0.97, blue: 0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(caution.opacity(0.45), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var termsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                createAcceptedTerms.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(inputBorder, lineWidth: 2)
                    )
                    .overlay {
                        if createAcceptedTerms {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(accent)
                        }
                    }
            }
            .buttonStyle(.plain)

            (
                Text("I agree to the ")
                    .foregroundColor(Color(red: 0.26, green: 0.35, blue: 0.46))
                + Text("Terms of Service")
                    .foregroundColor(Color(red: 0.11, green: 0.76, blue: 0.72))
                    .fontWeight(.bold)
                + Text(" and ")
                    .foregroundColor(Color(red: 0.26, green: 0.35, blue: 0.46))
                + Text("Privacy Policy")
                    .foregroundColor(Color(red: 0.11, green: 0.76, blue: 0.72))
                    .fontWeight(.bold)
            )
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authHero<TopContent: View>(
        title: String,
        subtitle: String,
        showsBackButton: Bool,
        heroHeight: CGFloat? = nil,
        @ViewBuilder topContent: () -> TopContent,
        onBack: (() -> Void)? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [accent, accent2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                if showsBackButton {
                    Button {
                        onBack?()
                    } label: {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color(red: 0.29, green: 0.39, blue: 0.51))
                            )
                    }
                    .buttonStyle(.plain)
                }

                topContent()
                    .padding(.top, showsBackButton ? 20 : 0)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 58, height: 58)
                    .overlay(
                        CareLoopBrandView(style: .icon, iconSize: 48)
                    )
                    .padding(.top, showsBackButton ? 8 : 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: showsBackButton ? 22 : 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: showsBackButton ? 14 : 19, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .padding(.top, showsBackButton ? 10 : 18)
            }
            .padding(.horizontal, 22)
            .padding(.top, showsBackButton ? 16 : 30)
        }
        .frame(height: heroHeight ?? (showsBackButton ? 250 : 240))
        .clipShape(HeroShape())
    }

    private func authTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(inputBorder, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func authSecureField(_ placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 18, weight: .medium, design: .rounded))

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(inputBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func gradientActionButton(title: String, disabled: Bool, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
            }
            .frame(height: 60)
            .background(
                LinearGradient(
                    colors: [accent, accent2],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: accent.opacity(0.22), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func continueDivider(_ title: String) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(inputBorder)
                .frame(height: 1)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryText)
            Rectangle()
                .fill(inputBorder)
                .frame(height: 1)
        }
    }

    private func socialButton(_ provider: AuthProvider) -> some View {
        Button {
            handleProviderTap(provider)
        } label: {
            authProviderVisual(provider)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private func authProviderCard(_ provider: AuthProvider) -> some View {
        Button {
            handleProviderTap(provider)
        } label: {
            authProviderVisual(provider)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private func authProviderVisual(_ provider: AuthProvider) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(inputBorder, lineWidth: 2)
                )

            switch provider {
            case .google:
                Image("GoogleLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            case .facebook:
                Image("FacebookLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
            case .email:
                Image(systemName: "envelope.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent2)
            }
        }
    }

    private func infoCard(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)

            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.35, blue: 0.46))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color(red: 0.92, green: 0.99, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func authError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
    }

    private func progressNode(index: Int, title: String, state: ForgotProgressState) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(state.background)
                    .frame(width: 40, height: 40)

                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(state.foreground)
                }
            }

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(state.labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressLine(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Color(red: 0.22, green: 0.80, blue: 0.27) : Color.white.opacity(0.28))
            .frame(height: 3)
            .offset(y: -14)
    }

    private var codeEntry: some View {
        ZStack {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 56, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(inputBorder, lineWidth: 2)
                        )
                        .overlay(
                            Text(character(at: index))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.26, green: 0.35, blue: 0.46))
                        )
                }
            }

            TextField("", text: $forgotCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .accentColor(.clear)
                .opacity(0.01)
                .onChange(of: forgotCode) { newValue in
                    forgotCode = String(newValue.filter(\.isNumber).prefix(6))
                }
        }
    }

    private func character(at index: Int) -> String {
        guard index < forgotCode.count else { return "" }
        let chars = Array(forgotCode)
        return String(chars[index])
    }

    private var canSignIn: Bool {
        OnboardingValidation.signIn(email: signInEmail, password: signInPassword)
    }

    private var canCreate: Bool {
        OnboardingValidation.signUp(
            name: createName,
            email: createEmail,
            password: createPassword,
            confirmPassword: createConfirmPassword,
            acceptedTerms: createAcceptedTerms
        )
    }

    private func resetSignUpState() {
        createName = ""
        createEmail = signInEmail
        createPassword = ""
        createConfirmPassword = ""
        createAcceptedTerms = false
        showCreatePassword = false
        showCreateConfirmPassword = false
        selectedProvider = .email
        error = nil
    }

    private func handleProviderTap(_ provider: AuthProvider) {
        error = nil
        selectedProvider = provider

        guard provider != .email else {
            if !showSignUp {
                resetSignUpState()
                showSignUp = true
            }
            return
        }

        loading = true
        Task {
            defer { loading = false }
            do {
                let payload = try await socialAuth.signIn(with: provider)
                let result = try await APIClient.shared.socialAuth(
                    provider: provider,
                    idToken: payload.idToken,
                    accessToken: payload.accessToken,
                    providerUserId: payload.providerUserId,
                    email: payload.email,
                    name: payload.name
                )
                try await finalizeAuthenticatedUser(result)
                showSignUp = false
                showForgotPassword = false
            } catch let authError as SocialAuthError {
                error = authError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitSignInTapped() {
        loading = true
        error = nil
        Task {
            do {
                try await submitSignIn()
            } catch let apiError as APIError {
                error = apiError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func submitCreateTapped() {
        loading = true
        error = nil
        Task {
            do {
                try await submitCreate()
                showSignUp = false
            } catch let apiError as APIError {
                error = apiError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func submitForgotEmail() {
        guard OnboardingValidation.recoveryEmail(email: forgotEmail) else {
            error = "Enter a valid email address."
            return
        }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                let result = try await APIClient.shared.requestPasswordReset(
                    email: forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                forgotDebugCode = result.debugCode
                forgotCode = result.debugCode ?? ""
                forgotStep = .verify
                forgotResendSeconds = 8
                startResendCountdown()
            } catch let apiError as APIError {
                error = apiError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitForgotVerify() {
        let candidateCode = forgotCode.isEmpty ? (forgotDebugCode ?? "") : forgotCode
        guard candidateCode.count == 6 else {
            error = "Enter the 6-digit code."
            return
        }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                _ = try await APIClient.shared.verifyPasswordResetCode(
                    email: forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: candidateCode
                )
                forgotCode = candidateCode
                forgotStep = .reset
            } catch let apiError as APIError {
                error = apiError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitForgotReset() {
        guard OnboardingValidation.resetPassword(password: forgotNewPassword, confirmPassword: forgotConfirmPassword) else {
            error = "Passwords must match and be at least \(OnboardingValidation.minimumPasswordLength) characters."
            return
        }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                _ = try await APIClient.shared.resetPassword(
                    email: forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: forgotCode,
                    password: forgotNewPassword
                )
                signInEmail = forgotEmail
                signInPassword = forgotNewPassword
                forgotDebugCode = nil
                showForgotPassword = false
            } catch let apiError as APIError {
                error = apiError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func startResendCountdown() {
        Task {
            while showForgotPassword && forgotStep == .verify && forgotResendSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if forgotResendSeconds > 0 {
                        forgotResendSeconds -= 1
                    }
                }
            }
        }
    }

    private func submitSignIn() async throws {
        guard OnboardingValidation.signIn(email: signInEmail, password: signInPassword) else {
            error = "Enter your email and a password with at least \(OnboardingValidation.minimumPasswordLength) characters."
            return
        }

        let result = try await APIClient.shared.logIn(
            email: signInEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            password: signInPassword
        )
        try await finalizeAuthenticatedUser(result)
    }

    private func submitCreate() async throws {
        guard OnboardingValidation.signUp(
            name: createName,
            email: createEmail,
            password: createPassword,
            confirmPassword: createConfirmPassword,
            acceptedTerms: createAcceptedTerms
        ) else {
            error = "Complete every field, match the passwords, and accept the terms."
            return
        }

        let result = try await APIClient.shared.signUp(
            email: createEmail.trimmingCharacters(in: .whitespaces),
            name: createName.trimmingCharacters(in: .whitespaces),
            password: createPassword,
            phone: nil
        )
        try await finalizeAuthenticatedUser(result)
    }

    private func finalizeAuthenticatedUser(_ result: AuthResult) async throws {
        APIClient.shared.setAccessToken(result.accessToken)
        let user = result.user
        let timezone = TimeZone.current.identifier
        _ = try? await APIClient.shared.updateTimezone(userId: user.id, timezone: timezone)
        appState.signIn(user: user, circle: nil)
    }
}

private enum ForgotPasswordStep: Int {
    case email = 1
    case verify = 2
    case reset = 3

    var title: String {
        switch self {
        case .email: return "Forgot password?"
        case .verify: return "Check your email"
        case .reset: return "New password"
        }
    }

    func subtitle(email: String) -> String {
        switch self {
        case .email:
            return "We'll send a 6-digit code to your email"
        case .verify:
            return "Code sent to \(email.isEmpty ? "your@email.com" : email)"
        case .reset:
            return "Make it strong and memorable"
        }
    }

    func progressState(for index: Int) -> ForgotProgressState {
        if rawValue > index { return .completed }
        if rawValue == index { return .current }
        return .upcoming
    }
}

private enum ForgotProgressState: Equatable {
    case completed
    case current
    case upcoming

    var background: Color {
        switch self {
        case .completed: return Color(red: 0.22, green: 0.80, blue: 0.27)
        case .current: return .white
        case .upcoming: return Color.white.opacity(0.20)
        }
    }

    var foreground: Color {
        switch self {
        case .completed: return .white
        case .current: return Color(red: 0.11, green: 0.76, blue: 0.72)
        case .upcoming: return .white.opacity(0.85)
        }
    }

    var labelColor: Color {
        switch self {
        case .completed, .current: return .white
        case .upcoming: return .white.opacity(0.55)
        }
    }
}

private struct HeroShape: Shape {
    func path(in rect: CGRect) -> Path {
        let rounded = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: 48, height: 48)
        )
        return Path(rounded.cgPath)
    }
}
