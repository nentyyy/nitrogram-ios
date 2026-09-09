import Foundation

/// Nitrogram's own feature flags.
///
/// Deliberately dependency-free and backed by `UserDefaults`, because these are
/// read from deep inside TelegramCore - on network queues, inside Postbox
/// transactions - where reaching for the app's settings machinery is not an
/// option.
///
/// Note: these live in the main app's defaults, so they apply to the app
/// process. Extensions (share, notification service) have their own defaults
/// domain and are not covered.
public struct NitrogramSettings {
    public enum Key: String {
        /// Never tell the server which messages have been read, so the sender
        /// keeps seeing a single check mark.
        case ghostReadReceipts = "nitrogram.ghost.readReceipts"
        /// Never report an online presence; the account stays "last seen a long
        /// time ago" as far as the server is concerned.
        case ghostOnlineStatus = "nitrogram.ghost.onlineStatus"
        /// Keep messages that the peer deleted, marked as deleted, instead of
        /// removing them from the chat.
        case keepDeletedMessages = "nitrogram.ghost.keepDeletedMessages"
        /// Replace the system keyboard with Nitrogram's own inside the app.
        case customKeyboard = "nitrogram.keyboard.custom"
    }

    /// Posted whenever any flag changes, so UI can refresh.
    public static let didChangeNotification = Notification.Name("NitrogramSettingsDidChange")

    public static func isEnabled(_ key: Key) -> Bool {
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    public static func setEnabled(_ value: Bool, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: NitrogramSettings.didChangeNotification, object: nil)
    }
}
