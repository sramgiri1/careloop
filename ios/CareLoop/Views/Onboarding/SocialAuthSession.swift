import AuthenticationServices
import Foundation
import UIKit

struct AuthCallbackPayload {
    let email: String?
    let name: String?
    let providerUserId: String?
    let idToken: String?
    let accessToken: String?
    let providerError: String?
}

enum SocialAuthError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    case callbackMissingData
    case provider(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Social sign-in is not configured yet."
        case .invalidConfiguration:
            return "Social sign-in URL is invalid."
        case .callbackMissingData:
            return "The provider returned without the account details CareLoop needs."
        case .provider(let message):
            return message
        case .cancelled:
            return "Sign-in was cancelled."
        }
    }
}

@MainActor
final class SocialAuthSession: NSObject, ObservableObject {
    @Published var activeProvider: AuthProvider?

    private var session: ASWebAuthenticationSession?

    func signIn(with provider: AuthProvider) async throws -> AuthCallbackPayload {
        guard provider != .email else {
            throw SocialAuthError.missingConfiguration
        }

        let config = try AuthProviderConfiguration.load(provider: provider)
        activeProvider = provider

        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: config.url,
                callbackURLScheme: config.callbackScheme
            ) { callbackURL, error in
                self.activeProvider = nil
                self.session = nil

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: SocialAuthError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SocialAuthError.callbackMissingData)
                    return
                }

                let payload = AuthProviderConfiguration.parseCallback(url: callbackURL)
                if let providerError = payload.providerError, !providerError.isEmpty {
                    continuation.resume(throwing: SocialAuthError.provider(providerError))
                    return
                }
                if payload.email == nil && payload.name == nil && payload.providerUserId == nil && payload.idToken == nil && payload.accessToken == nil {
                    continuation.resume(throwing: SocialAuthError.callbackMissingData)
                } else {
                    continuation.resume(returning: payload)
                }
            }

            authSession.prefersEphemeralWebBrowserSession = true
            authSession.presentationContextProvider = self
            self.session = authSession

            if !authSession.start() {
                self.activeProvider = nil
                self.session = nil
                continuation.resume(throwing: SocialAuthError.invalidConfiguration)
            }
        }
    }
}

extension SocialAuthSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

struct AuthProviderConfiguration {
    let url: URL
    let callbackScheme: String

    static func load(provider: AuthProvider) throws -> AuthProviderConfiguration {
        guard
            let baseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            !baseURL.isEmpty,
            let callbackScheme = Bundle.main.object(forInfoDictionaryKey: "AUTH_CALLBACK_SCHEME") as? String,
            !callbackScheme.isEmpty
        else {
            throw SocialAuthError.missingConfiguration
        }

        let slug = switch provider {
        case .email: "email"
        case .google: "google"
        case .facebook: "facebook"
        case .apple: "apple"
        }

        guard var components = URLComponents(string: baseURL) else {
            throw SocialAuthError.invalidConfiguration
        }
        components.path = "/auth/oauth/\(slug)/start"
        components.queryItems = [
            URLQueryItem(name: "callback_scheme", value: callbackScheme)
        ]

        guard let url = components.url else {
            throw SocialAuthError.invalidConfiguration
        }

        return AuthProviderConfiguration(url: url, callbackScheme: callbackScheme)
    }

    static func parseCallback(url: URL) -> AuthCallbackPayload {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let email = components?.queryItems?.first(where: { $0.name == "email" })?.value
        let name = components?.queryItems?.first(where: { $0.name == "name" })?.value
        let providerUserId = components?.queryItems?.first(where: { $0.name == "provider_user_id" || $0.name == "sub" || $0.name == "id" })?.value
        let idToken = components?.queryItems?.first(where: { $0.name == "id_token" })?.value
        let accessToken = components?.queryItems?.first(where: { $0.name == "access_token" })?.value
        let providerError = components?.queryItems?.first(where: { $0.name == "error" })?.value
        return AuthCallbackPayload(
            email: email,
            name: name,
            providerUserId: providerUserId,
            idToken: idToken,
            accessToken: accessToken,
            providerError: providerError
        )
    }
}
