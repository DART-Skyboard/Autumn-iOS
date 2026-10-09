import Foundation

/// The user's own sharing choices (Profile > Privacy). Everything here is OFF until the user turns it on.
/// Nothing in this list is required to use Autumn: chat, journal on device, agents and Tool Radian all work with every switch off.
public enum PrivacyChoices {
    public static let analyticsKey = "privacy.shareAnalytics"
    public static let presenceKey  = "privacy.sharePresence"
    public static let locationKey  = "privacy.shareLocation"
    public static let journalKey   = "privacy.shareJournal"

    private static func flag(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }   // absent = false (opt-in)
    /// Anonymous usage events (which reflex stage / tool / emotion ran). Written to the analytics log.
    public static var shareAnalytics: Bool { flag(analyticsKey) }
    /// Show this device as a presence node to other sessions, and send presence pings.
    public static var sharePresence: Bool { flag(presenceKey) }
    /// Send your chat messages to Autumn's journal (and study queue) in the GitHub repo through the Apps Script. Off = chats stay on this device.
    public static var shareJournal: Bool { flag(journalKey) }
    /// Use your location for Mantis Radar (nearby aircraft). Your coordinates go to the public ADS-B feeds to fetch that area.
    public static var shareLocation: Bool { flag(locationKey) }
}
