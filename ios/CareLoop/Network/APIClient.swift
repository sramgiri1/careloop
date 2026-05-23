import Foundation

private struct APIErrorBody: Decodable {
    let error: String
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let accessTokenKey = "careloop.accessToken"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = fractional.date(from: str) { return date }
            if let date = basic.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot decode ISO8601 date: \(str)")
        }
        return d
    }()

    private init() {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        else { fatalError("API_BASE_URL must be set in Info.plist") }
        self.baseURL = url
    }

    var hasAccessToken: Bool {
        accessToken?.isEmpty == false
    }

    func setAccessToken(_ token: String) {
        KeychainStore.set(token, for: accessTokenKey)
    }

    func clearAccessToken() {
        KeychainStore.remove(accessTokenKey)
    }

    func revokeCurrentAccessTokenForSignOut() {
        guard let token = accessToken else { return }
        Task {
            try? await requestVoid(
                path: "/auth/logout",
                method: "POST",
                body: Data("{}".utf8),
                accessTokenOverride: token
            )
        }
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil as Data?)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(path: path, method: "POST", body: data)
    }

    func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(path: path, method: "PATCH", body: data)
    }

    func patchAny<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await request(path: path, method: "PATCH", body: data)
    }

    func postAny<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await request(path: path, method: "POST", body: data)
    }

    func putAny<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await request(path: path, method: "PUT", body: data)
    }

    func putAnyVoid(_ path: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        try await requestVoid(path: path, method: "PUT", body: data)
    }

    func deleteVoid(_ path: String, body: [String: Any]? = nil) async throws {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        try await requestVoid(path: path, method: "DELETE", body: data)
    }

    private func requestVoid(
        path: String,
        method: String,
        body: Data?,
        accessTokenOverride: String? = nil
    ) async throws {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let bearerToken = accessTokenOverride ?? accessToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = try? decoder.decode(APIErrorBody.self, from: data).error
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
    }

    private func request<T: Decodable>(path: String, method: String, body: Data?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = try? decoder.decode(APIErrorBody.self, from: data).error
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
        return try decoder.decode(T.self, from: data)
    }

    private var accessToken: String? {
        KeychainStore.get(accessTokenKey)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "Invalid URL"
        case .httpError(let c, let message): return message ?? "Server error \(c)"
        }
    }
}
