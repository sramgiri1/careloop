import Foundation

enum AuthProvider: String, CaseIterable {
    case email = "Email"
    case google = "Google"
    case facebook = "Facebook"
    case apple = "Apple"

    var apiValue: String {
        switch self {
        case .email: return "EMAIL"
        case .google: return "GOOGLE"
        case .facebook: return "FACEBOOK"
        case .apple: return "APPLE"
        }
    }
}

enum OnboardingValidation {
    static let minimumPasswordLength = 8

    static func signIn(email: String, password: String) -> Bool {
        isEmailLike(email) && isStrongEnough(password)
    }

    static func joinCircle(circleId: String) -> Bool {
        !trimmed(circleId).isEmpty
    }

    static func createCircle(circleName: String) -> Bool {
        !trimmed(circleName).isEmpty
    }

    static func signUp(name: String, email: String, password: String, confirmPassword: String, acceptedTerms: Bool) -> Bool {
        !trimmed(name).isEmpty &&
        isEmailLike(email) &&
        isStrongEnough(password) &&
        password == confirmPassword &&
        acceptedTerms
    }

    static func recoveryEmail(email: String) -> Bool {
        isEmailLike(email)
    }

    static func resetPassword(password: String, confirmPassword: String) -> Bool {
        isStrongEnough(password) && password == confirmPassword
    }

    static func helperText(for provider: AuthProvider) -> String {
        switch provider {
        case .email:
            return "Create an account with your email and password."
        case .google:
            return "Google sign-in creates or resumes your CareLoop account."
        case .facebook:
            return "Facebook sign-in creates or resumes your CareLoop account."
        case .apple:
            return "Apple sign-in creates or resumes your CareLoop account."
        }
    }

    private static func isEmailLike(_ value: String) -> Bool {
        let email = trimmed(value)
        return email.contains("@") && email.contains(".")
    }

    private static func isStrongEnough(_ value: String) -> Bool {
        trimmed(value).count >= minimumPasswordLength
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
