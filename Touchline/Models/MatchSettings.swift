//
//  MatchSettings.swift
//  Touchline
//
//  User preferences controlling how live matches are played back and how the
//  team is automatically managed during a match.
//

import Foundation

public struct MatchSettings: Codable, Hashable {

    /// Playback speed of the live match replay.
    public enum Speed: String, Codable, CaseIterable, Identifiable, Hashable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case veryFast = "Very Fast"

        public var id: String { rawValue }

        /// Real seconds per match minute. In match time per real second:
        /// Slow 30 seconds, Normal 1 minute, Fast 2 minutes, Very Fast 3
        /// minutes.
        public var tickInterval: Double {
            switch self {
            case .slow: return 2.0
            case .normal: return 1.0
            case .fast: return 0.5
            case .veryFast: return 1.0 / 3.0
            }
        }

        public var displayName: String { rawValue }
    }

    /// When automatic substitutions should occur.
    public enum AutoSubTiming: String, Codable, CaseIterable, Identifiable, Hashable {
        case off = "Off"
        case halfTime = "At Half-Time"
        case secondHalf = "In the Second Half"
        case throughout = "Throughout"

        public var id: String { rawValue }
        public var displayName: String { rawValue }
    }

    /// How aggressively the assistant manager rotates players.
    public enum AutoSubAggression: String, Codable, CaseIterable, Identifiable, Hashable {
        case conservative = "Conservative"
        case balanced = "Balanced"
        case aggressive = "Aggressive"

        public var id: String { rawValue }
        public var displayName: String { rawValue }

        /// In-match tiredness (0-100; a full ninety minutes at a normal
        /// press leaves a player around 30) above which he is replaced.
        public var fatigueThreshold: Double {
            switch self {
            case .conservative: return 24
            case .balanced: return 18
            case .aggressive: return 13
            }
        }

        /// Maximum substitutions the assistant will make.
        public var maxSubs: Int {
            switch self {
            case .conservative: return 3
            case .balanced: return 5
            case .aggressive: return 5
            }
        }
    }

    /// Playback speed for replaying a live match.
    public var speed: Speed
    /// Pause the replay at half-time to let the manager make changes.
    public var stopAtHalfTime: Bool
    /// When the assistant manager makes automatic substitutions.
    public var autoSubTiming: AutoSubTiming
    /// How aggressively the assistant rotates players.
    public var autoSubAggression: AutoSubAggression
    /// Before each match the assistant rests tired starters for fresh squad
    /// players of similar quality (manager mode).
    public var assistantRotatesTiredPlayers: Bool
    public var autoSelectMatchdayLineup: Bool
    /// Continue shows the days ticking by on an animated calendar rather than
    /// jumping straight to the next match day.
    public var animateCalendar: Bool
    /// The animated calendar stops to show important new mail.
    public var pauseCalendarForMail: Bool
    /// A live match stops when one of your players is hurt, so you choose
    /// his replacement.
    public var stopForInjuries: Bool

    public init(
        speed: Speed = .normal,
        stopAtHalfTime: Bool = true,
        autoSubTiming: AutoSubTiming = .off,
        autoSubAggression: AutoSubAggression = .balanced,
        assistantRotatesTiredPlayers: Bool = false,
        animateCalendar: Bool = true,
        pauseCalendarForMail: Bool = true,
        stopForInjuries: Bool = true,
        autoSelectMatchdayLineup: Bool = false
    ) {
        self.speed = speed
        self.stopAtHalfTime = stopAtHalfTime
        self.autoSubTiming = autoSubTiming
        self.autoSubAggression = autoSubAggression
        self.assistantRotatesTiredPlayers = assistantRotatesTiredPlayers
        self.animateCalendar = animateCalendar
        self.pauseCalendarForMail = pauseCalendarForMail
        self.stopForInjuries = stopForInjuries
        self.autoSelectMatchdayLineup = autoSelectMatchdayLineup
    }

    private enum CodingKeys: String, CodingKey {
        case speed, stopAtHalfTime, autoSubTiming, autoSubAggression, assistantRotatesTiredPlayers, animateCalendar, pauseCalendarForMail
        case stopForInjuries, controlVersion, autoSelectMatchdayLineup
    }

    /// Version 2: the manager makes his own substitutions unless he hands
    /// them to the assistant. Older settings had the assistant subbing by
    /// default, so that is switched off once on upgrade.
    private static let currentControlVersion = 2

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoSelectMatchdayLineup, forKey: .autoSelectMatchdayLineup)
        try c.encode(speed, forKey: .speed)
        try c.encode(stopAtHalfTime, forKey: .stopAtHalfTime)
        try c.encode(autoSubTiming, forKey: .autoSubTiming)
        try c.encode(autoSubAggression, forKey: .autoSubAggression)
        try c.encode(assistantRotatesTiredPlayers, forKey: .assistantRotatesTiredPlayers)
        try c.encode(animateCalendar, forKey: .animateCalendar)
        try c.encode(pauseCalendarForMail, forKey: .pauseCalendarForMail)
        try c.encode(stopForInjuries, forKey: .stopForInjuries)
        try c.encode(MatchSettings.currentControlVersion, forKey: .controlVersion)
    }

    /// Tolerant decoding so settings saved by older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoSelectMatchdayLineup = try c.decodeIfPresent(Bool.self, forKey: .autoSelectMatchdayLineup) ?? false
        speed = try c.decodeIfPresent(Speed.self, forKey: .speed) ?? .normal
        stopAtHalfTime = try c.decodeIfPresent(Bool.self, forKey: .stopAtHalfTime) ?? true
        autoSubTiming = try c.decodeIfPresent(AutoSubTiming.self, forKey: .autoSubTiming) ?? .secondHalf
        autoSubAggression = try c.decodeIfPresent(AutoSubAggression.self, forKey: .autoSubAggression) ?? .balanced
        assistantRotatesTiredPlayers = try c.decodeIfPresent(Bool.self, forKey: .assistantRotatesTiredPlayers) ?? false
        animateCalendar = try c.decodeIfPresent(Bool.self, forKey: .animateCalendar) ?? true
        pauseCalendarForMail = try c.decodeIfPresent(Bool.self, forKey: .pauseCalendarForMail) ?? true
        stopForInjuries = try c.decodeIfPresent(Bool.self, forKey: .stopForInjuries) ?? true
        let version = try c.decodeIfPresent(Int.self, forKey: .controlVersion) ?? 1
        if version < MatchSettings.currentControlVersion {
            autoSubTiming = .off
            assistantRotatesTiredPlayers = false
        }
    }
}
