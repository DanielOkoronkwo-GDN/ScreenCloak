//
//  ProtectionOptions.swift
//  ScreenCloak
//

/// Which situations hide protected content.
public struct ProtectionOptions: OptionSet, Sendable {
    public let rawValue: Int

    /// Hide the view from screenshots.
    public static let screenshots = ProtectionOptions(rawValue: 0x01)
    /// Hide the view from screen sharing (e.g. AirPlay) and screen recording.
    public static let screenSharing = ProtectionOptions(rawValue: 0x02)
    /// Hide the view while the app is not active (e.g. while task switching).
    public static let inactivity = ProtectionOptions(rawValue: 0x04)
    /// Hide the view from screenshots, screen sharing and during inactivity (task switching).
    public static let all: ProtectionOptions = [.screenshots, .screenSharing, .inactivity]

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
