import XCTest
@testable import CareLoop

final class OnboardingValidationTests: XCTestCase {

    func test_signIn_requiresEmailAndPassword() {
        XCTAssertFalse(OnboardingValidation.signIn(email: "", password: ""))
        XCTAssertFalse(OnboardingValidation.signIn(email: "alex@example.com", password: "short"))
        XCTAssertTrue(OnboardingValidation.signIn(email: "alex@example.com", password: "password1"))
    }

    func test_joinCircle_requiresCircleIdOnly() {
        XCTAssertFalse(OnboardingValidation.joinCircle(circleId: "   "))
        XCTAssertTrue(OnboardingValidation.joinCircle(circleId: "circle-123"))
    }

    func test_createCircle_requiresCircleName() {
        XCTAssertFalse(OnboardingValidation.createCircle(circleName: ""))
        XCTAssertTrue(OnboardingValidation.createCircle(circleName: "Family"))
    }

    func test_supportedCreateAccountProviders_includeEmailGoogleFacebookApple() {
        XCTAssertEqual(AuthProvider.allCases, [.email, .google, .facebook, .apple])
    }

    func test_signUp_requiresAcceptedTermsAndMatchingPasswords() {
        XCTAssertFalse(
            OnboardingValidation.signUp(
                name: "Alex",
                email: "alex@example.com",
                password: "password1",
                confirmPassword: "password1",
                acceptedTerms: false
            )
        )

        XCTAssertTrue(
            OnboardingValidation.signUp(
                name: "Alex",
                email: "alex@example.com",
                password: "password1",
                confirmPassword: "password1",
                acceptedTerms: true
            )
        )
    }

    func test_resetPassword_requiresMatchingStrongPasswords() {
        XCTAssertFalse(OnboardingValidation.resetPassword(password: "short", confirmPassword: "short"))
        XCTAssertFalse(OnboardingValidation.resetPassword(password: "password1", confirmPassword: "password2"))
        XCTAssertTrue(OnboardingValidation.resetPassword(password: "password1", confirmPassword: "password1"))
    }

    func test_socialProviderHelperText_mentionsAccountAccess() {
        XCTAssertTrue(OnboardingValidation.helperText(for: .google).contains("CareLoop account"))
        XCTAssertTrue(OnboardingValidation.helperText(for: .facebook).contains("CareLoop account"))
        XCTAssertTrue(OnboardingValidation.helperText(for: .apple).contains("CareLoop account"))
    }

    func test_authCallbackParsing_readsEmailAndName() {
        let url = URL(string: "careloop://auth?email=alex%40example.com&name=Alex%20Caregiver")!
        let payload = AuthProviderConfiguration.parseCallback(url: url)
        XCTAssertEqual(payload.email, "alex@example.com")
        XCTAssertEqual(payload.name, "Alex Caregiver")
    }
}
