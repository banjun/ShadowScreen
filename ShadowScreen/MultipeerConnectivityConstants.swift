import Foundation
import MultipeerConnectivity

struct Env {
    static var shared: Env = .init()

    var CFBundleIdentifier: String?

    private init() {
        let info = Bundle.main.infoDictionary!
        CFBundleIdentifier = info["CFBundleIdentifier"] as? String
    }
}

enum MultipeerConnectivityConstants {
    /// MultipeerConnectivity service type
    /// The type of service to advertise. This should be a short text string that describes the app's networking protocol, in the same format as a Bonjour service type (without the transport protocol) and meeting the restrictions of RFC 6335 (section 5.1) governing Service Name Syntax. In particular, the string:
    /// * Must be 1–15 characters long
    /// * Can contain only ASCII lowercase letters, numbers, and hyphens
    /// * Must contain at least one ASCII letter
    /// * Must not begin or end with a hyphen
    /// * Must not contain hyphens adjacent to other hyphens.
    static let serviceType = "shadowscreen"
    static let serverDiscoveryInfo: [String: String] = ["ShadowScreenServer": "1"]
}
