//
//  Match.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Match simulation output models including MatchResult, timeline MatchEvent,
//  and team MatchStats tracking expected goals (xG), possession, and discipline.
//

import Foundation

// MARK: - Match Result

public struct PenaltyShootout: Codable, Hashable {
    public let home: Int
    public let away: Int

    public var scoreText: String { "\(home)-\(away) on penalties" }
}

public struct MatchResult: Codable, Identifiable, Hashable {
    public let id: UUID
    public var homeClubId: UUID
    public var awayClubId: UUID
    public var homeGoals: Int
    public var awayGoals: Int
    public var shootout: PenaltyShootout?
    public var events: [MatchEvent]
    public var matchWeek: Int
    public var competition: String       // e.g., "Premier League", "FA Cup Third Round"
    public var date: String              // "YYYY-MM-DD"
    public var attendance: Int
    public var homeStats: MatchStats
    public var awayStats: MatchStats
    public var playerRatings: [UUID: Double]  // Player UUID -> Match Rating (1.0 to 10.0)
    public var manOfTheMatch: UUID?
    
    public init(
        id: UUID = UUID(),
        homeClubId: UUID,
        awayClubId: UUID,
        homeGoals: Int,
        awayGoals: Int,
        events: [MatchEvent] = [],
        matchWeek: Int,
        competition: String,
        date: String,
        attendance: Int,
        homeStats: MatchStats = .empty,
        awayStats: MatchStats = .empty,
        playerRatings: [UUID: Double] = [:],
        manOfTheMatch: UUID? = nil
    ) {
        self.id = id
        self.homeClubId = homeClubId
        self.awayClubId = awayClubId
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.shootout = nil
        self.events = events
        self.matchWeek = matchWeek
        self.competition = competition
        self.date = date
        self.attendance = attendance
        self.homeStats = homeStats
        self.awayStats = awayStats
        self.playerRatings = playerRatings
        self.manOfTheMatch = manOfTheMatch
    }
    
    // MARK: - Compact Coding

    // Archived results (most of the world's fixtures) have no events, ratings
    // or stats. Leaving those keys out instead of writing empty arrays and
    // zeroed stat blocks keeps saves small; decoding treats missing keys as
    // empty, so older saves still load.
    private enum CodingKeys: String, CodingKey {
        case id, homeClubId, awayClubId, homeGoals, awayGoals, shootout, events, matchWeek
        case competition, date, attendance, homeStats, awayStats, playerRatings, manOfTheMatch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        homeClubId = try c.decode(UUID.self, forKey: .homeClubId)
        awayClubId = try c.decode(UUID.self, forKey: .awayClubId)
        homeGoals = try c.decode(Int.self, forKey: .homeGoals)
        awayGoals = try c.decode(Int.self, forKey: .awayGoals)
        shootout = try c.decodeIfPresent(PenaltyShootout.self, forKey: .shootout)
        events = try c.decodeIfPresent([MatchEvent].self, forKey: .events) ?? []
        matchWeek = try c.decodeIfPresent(Int.self, forKey: .matchWeek) ?? 0
        competition = try c.decodeIfPresent(String.self, forKey: .competition) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        attendance = try c.decodeIfPresent(Int.self, forKey: .attendance) ?? 0
        homeStats = try c.decodeIfPresent(MatchStats.self, forKey: .homeStats) ?? .empty
        awayStats = try c.decodeIfPresent(MatchStats.self, forKey: .awayStats) ?? .empty
        playerRatings = try c.decodeIfPresent([UUID: Double].self, forKey: .playerRatings) ?? [:]
        manOfTheMatch = try c.decodeIfPresent(UUID.self, forKey: .manOfTheMatch)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(homeClubId, forKey: .homeClubId)
        try c.encode(awayClubId, forKey: .awayClubId)
        try c.encode(homeGoals, forKey: .homeGoals)
        try c.encode(awayGoals, forKey: .awayGoals)
        try c.encodeIfPresent(shootout, forKey: .shootout)
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        try c.encode(matchWeek, forKey: .matchWeek)
        try c.encode(competition, forKey: .competition)
        try c.encode(date, forKey: .date)
        if attendance != 0 { try c.encode(attendance, forKey: .attendance) }
        if homeStats != .empty { try c.encode(homeStats, forKey: .homeStats) }
        if awayStats != .empty { try c.encode(awayStats, forKey: .awayStats) }
        if !playerRatings.isEmpty { try c.encode(playerRatings, forKey: .playerRatings) }
        try c.encodeIfPresent(manOfTheMatch, forKey: .manOfTheMatch)
    }

    // MARK: - Computed Properties
    
    public var scoreText: String {
        return "\(homeGoals) - \(awayGoals)" + (shootout.map { " (\($0.scoreText))" } ?? "")
    }
    
    public var isDraw: Bool {
        return homeGoals == awayGoals && shootoutWinnerClubId == nil
    }
    
    public var shootoutWinnerClubId: UUID? {
        guard let shootout, shootout.home != shootout.away else { return nil }
        return shootout.home > shootout.away ? homeClubId : awayClubId
    }

    public var winnerClubId: UUID? {
        if let winner = shootoutWinnerClubId { return winner }
        if homeGoals > awayGoals {
            return homeClubId
        } else if awayGoals > homeGoals {
            return awayClubId
        } else {
            return nil
        }
    }
    
    /// Returns "W", "D", or "L" from the vantage point of a designated club.
    public func outcomeLetter(for clubId: UUID) -> String {
        guard clubId == homeClubId || clubId == awayClubId else { return "-" }
        guard let winner = winnerClubId else { return "D" }
        return winner == clubId ? "W" : "L"
    }
    
    /// A slimmed copy for matches the user did not play in. Keeps the score,
    /// stats, man of the match and key events (goals, cards, injuries), but drops
    /// minute-by-minute commentary and per-player ratings.
    ///
    /// Every world fixture's full result used to be stored three times (on the
    /// fixture and on both clubs), adding ~7 MB to the save each week and
    /// pushing a single season's save past 300 MB.
    public func compactedForArchive() -> MatchResult {
        // Only the score is ever read for matches the user did not play
        // (tables, cup brackets, "elsewhere" results). Keeping events and team
        // stats for ~12,000 fixtures added ~40 MB to every save and most of
        // the memory used while encoding it.
        var copy = self
        copy.events = []
        copy.playerRatings = [:]
        copy.homeStats = .empty
        copy.awayStats = .empty
        return copy
    }

    /// Score and stats only. Used for the per-club results history of clubs the
    /// user does not control, which nothing in the game reads event-by-event.
    public func scoreOnly() -> MatchResult {
        var copy = self
        copy.events = []
        copy.playerRatings = [:]
        return copy
    }

    /// Whether this result is already in archived form.
    public var isCompacted: Bool {
        playerRatings.isEmpty && events.isEmpty
    }

    /// List of goal events recorded during this fixture.
    public var goalEvents: [MatchEvent] {
        return events.filter { $0.type == .goal || $0.type == .ownGoal || $0.type == .penalty }
    }
    
    /// Major timeline highlights for quick post-match reviews.
    public var majorEvents: [MatchEvent] {
        return events.filter { $0.type.isMajorEvent }
    }
}

// MARK: - Match Event

public struct MatchEvent: Codable, Identifiable, Hashable {
    public let id: UUID
    public var minute: Int
    public var type: MatchEventType
    public var clubId: UUID?
    public var playerId: UUID?
    public var assistPlayerId: UUID?
    public var shortText: String        // Single line commentary header (e.g., "GOAL! B. Fernandes 23'")
    public var detailText: String       // Full expanded narrative description for commentary view
    public var isHomeTeam: Bool
    
    public init(
        id: UUID = UUID(),
        minute: Int,
        type: MatchEventType,
        clubId: UUID? = nil,
        playerId: UUID? = nil,
        assistPlayerId: UUID? = nil,
        shortText: String,
        detailText: String = "",
        isHomeTeam: Bool
    ) {
        self.id = id
        self.minute = minute
        self.type = type
        self.clubId = clubId
        self.playerId = playerId
        self.assistPlayerId = assistPlayerId
        self.shortText = shortText
        self.detailText = detailText.isEmpty ? shortText : detailText
        self.isHomeTeam = isHomeTeam
    }
    
    public var minuteDisplay: String {
        return "\(minute)'"
    }
}

// MARK: - Match Stats

public struct MatchStats: Codable, Hashable {
    public var possession: Double       // Percentage (e.g., 52.4)
    public var shots: Int
    public var shotsOnTarget: Int
    public var corners: Int
    public var fouls: Int
    public var offsides: Int
    public var passAccuracy: Double     // Percentage (e.g., 84.0)
    public var tacklesWon: Int
    public var saves: Int
    public var xG: Double               // Expected goals (e.g., 1.84)
    
    public init(
        possession: Double = 50.0,
        shots: Int = 0,
        shotsOnTarget: Int = 0,
        corners: Int = 0,
        fouls: Int = 0,
        offsides: Int = 0,
        passAccuracy: Double = 80.0,
        tacklesWon: Int = 0,
        saves: Int = 0,
        xG: Double = 0.0
    ) {
        self.possession = possession
        self.shots = shots
        self.shotsOnTarget = shotsOnTarget
        self.corners = corners
        self.fouls = fouls
        self.offsides = offsides
        self.passAccuracy = passAccuracy
        self.tacklesWon = tacklesWon
        self.saves = saves
        self.xG = xG
    }
    
    public static var empty: MatchStats {
        return MatchStats()
    }
}

// MARK: - Season Review

/// The user's completed season, summarised for the end-of-season card.
public struct SeasonReview: Codable, Hashable {
    public var season: String
    public var clubName: String
    public var leagueName: String
    public var position: Int
    public var leagueSize: Int
    public var points: Int
    public var won: Int
    public var drawn: Int
    public var lost: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var targetGoal: String?
    public var targetMet: Bool?
    public var cupRun: String?
    public var topScorer: String?
    public var playerOfSeason: String?
    public var europe: String?
    /// The league cup (and any other domestic trophy) run.
    public var leagueCupRun: String? = nil
    /// How far the club went in each European competition it played in.
    public var europeanRuns: [String]? = nil
    /// The division's top three clubs, best three players, top scorers and
    /// top providers, and its team of the season.
    public var topClubs: [String]? = nil
    public var bestPlayers: [AwardEntry]? = nil
    public var topScorers: [AwardEntry]? = nil
    public var topAssists: [AwardEntry]? = nil
    public var teamOfTheSeason: [AwardEntry]? = nil
    /// The same for every other division in the world.
    public var otherDivisions: [DivisionHonours]? = nil
}
