import Foundation

#if DEBUG
struct DemoLaunchSession {
    private enum EnvironmentKeys {
        static let accessToken = "CARELOOP_DEMO_ACCESS_TOKEN"
        static let circleId = "CARELOOP_DEMO_CIRCLE_ID"
        static let autoActivate = "CARELOOP_DEMO_AUTO_ACTIVATE"
    }

    let accessToken: String
    let circleId: String?
    let autoActivateCircle: Bool

    static var current: DemoLaunchSession? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let rawToken = environment[EnvironmentKeys.accessToken]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawToken.isEmpty else {
            return nil
        }

        let rawCircleId = environment[EnvironmentKeys.circleId]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let circleId = rawCircleId?.isEmpty == false ? rawCircleId : nil

        return DemoLaunchSession(
            accessToken: rawToken,
            circleId: circleId,
            autoActivateCircle: flagEnabled(environment[EnvironmentKeys.autoActivate]) && circleId != nil
        )
        #else
        nil
        #endif
    }

    private static func flagEnabled(_ rawValue: String?) -> Bool {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
#endif
