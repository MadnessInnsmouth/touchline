//
//  League.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  League structures, seasonal schedules, round-robin fixture generation,
//  and dynamic league table standings calculations.
//

import Foundation

// MARK: - League Model

public struct League: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var tier: LeagueTier
    public var clubIds: [UUID]
    
    public init(
        id: UUID = UUID(),
        name: String,
        tier: LeagueTier,
        clubIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.tier = tier
        self.clubIds = clubIds
    }
}

// MARK: - Season Model

public struct Season: Codable, Hashable {
    public var year: String                 // e.g., "2026-27"
    public var currentWeek: Int             // Matchweek index (1 to 46)
    public var currentPhase: SeasonPhase
    public var fixtures: [Fixture]
    public var currentDate: String          // In-game calendar date "YYYY-MM-DD"
    
    public init(
        year: String = "2026-27",
        currentWeek: Int = 1,
        currentPhase: SeasonPhase = .inSeason,
        fixtures: [Fixture] = [],
        currentDate: String = "2026-08-08"
    ) {
        self.year = year
        self.currentWeek = currentWeek
        self.currentPhase = currentPhase
        self.fixtures = fixtures
        self.currentDate = currentDate
    }
    
    // MARK: - Fixture Queries
    
    public func fixtures(forWeek week: Int) -> [Fixture] {
        return fixtures.filter { $0.matchWeek == week }
    }
    
    public var currentWeekFixtures: [Fixture] {
        return fixtures(forWeek: currentWeek)
    }
    
    public func upcomingFixtures(forClub clubId: UUID) -> [Fixture] {
        return fixtures
            .filter { $0.involves(clubId: clubId) && !$0.isPlayed }
            .sorted { ($0.matchWeek, $0.date) < ($1.matchWeek, $1.date) }
    }
    
    public func completedFixtures(forClub clubId: UUID) -> [Fixture] {
        return fixtures
            .filter { $0.involves(clubId: clubId) && $0.isPlayed }
            .sorted { ($0.matchWeek, $0.date) < ($1.matchWeek, $1.date) }
    }
    
    public func nextFixture(forClub clubId: UUID) -> Fixture? {
        return upcomingFixtures(forClub: clubId).first
    }
    
    public var totalMatchWeeks: Int {
        return fixtures.map { $0.matchWeek }.max() ?? 38
    }
    
    public var isSeasonFinished: Bool {
        return currentWeek > totalMatchWeeks
    }
}

// MARK: - Fixture Model

public struct Fixture: Codable, Identifiable, Hashable {
    public let id: UUID
    public var homeClubId: UUID
    public var awayClubId: UUID
    public var matchWeek: Int
    public var date: String                 // "YYYY-MM-DD"
    public var competition: String
    public var isPlayed: Bool
    public var result: MatchResult?
    /// Set for domestic-cup ties (e.g. "Quarter-Final"); nil for league games.
    /// Cup ties are knockouts decided by extra time and penalties if needed.
    public var cupRound: String?
    /// For the user's European ties, which are played as normal match days:
    /// the id of the matching fixture in the European competition.
    public var europeanFixtureId: UUID?
    
    public init(
        id: UUID = UUID(),
        homeClubId: UUID,
        awayClubId: UUID,
        matchWeek: Int,
        date: String,
        competition: String,
        isPlayed: Bool = false,
        result: MatchResult? = nil,
        cupRound: String? = nil,
        europeanFixtureId: UUID? = nil
    ) {
        self.id = id
        self.homeClubId = homeClubId
        self.awayClubId = awayClubId
        self.matchWeek = matchWeek
        self.date = date
        self.competition = competition
        self.isPlayed = isPlayed
        self.result = result
        self.cupRound = cupRound
        self.europeanFixtureId = europeanFixtureId
    }

    public var isCupTie: Bool { cupRound != nil }
    public var isEuropean: Bool { europeanFixtureId != nil }

    /// The club that won the match or its shootout.
    public var winnerClubId: UUID? {
        isPlayed ? result?.winnerClubId : nil
    }
    

    public func involves(clubId: UUID) -> Bool {
        return homeClubId == clubId || awayClubId == clubId
    }
    
    public func opponentId(for clubId: UUID) -> UUID? {
        if homeClubId == clubId { return awayClubId }
        if awayClubId == clubId { return homeClubId }
        return nil
    }
}

// MARK: - League Standing

public struct LeagueStanding: Codable, Hashable, Identifiable {
    public var id: UUID { clubId }
    public var clubId: UUID
    public var played: Int
    public var won: Int
    public var drawn: Int
    public var lost: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var goalDifference: Int
    public var points: Int
    public var form: [String]               // Last 5 outcomes: ["W", "D", "L", "W", "W"]
    
    public init(
        clubId: UUID,
        played: Int = 0,
        won: Int = 0,
        drawn: Int = 0,
        lost: Int = 0,
        goalsFor: Int = 0,
        goalsAgainst: Int = 0,
        goalDifference: Int = 0,
        points: Int = 0,
        form: [String] = []
    ) {
        self.clubId = clubId
        self.played = played
        self.won = won
        self.drawn = drawn
        self.lost = lost
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.goalDifference = goalDifference
        self.points = points
        self.form = form
    }
    
    /// Records a single match outcome into this standing record.
    public mutating func recordResult(goalsFor: Int, goalsAgainst: Int) {
        self.played += 1
        self.goalsFor += goalsFor
        self.goalsAgainst += goalsAgainst
        self.goalDifference = self.goalsFor - self.goalsAgainst
        
        if goalsFor > goalsAgainst {
            self.won += 1
            self.points += 3
            appendForm("W")
        } else if goalsFor == goalsAgainst {
            self.drawn += 1
            self.points += 1
            appendForm("D")
        } else {
            self.lost += 1
            appendForm("L")
        }
    }
    
    private mutating func appendForm(_ resultLetter: String) {
        form.append(resultLetter)
        if form.count > 5 {
            form.removeFirst()
        }
    }
    
    /// Sorting comparator standard for association football tables.
    public static func standardSort(lhs: LeagueStanding, rhs: LeagueStanding) -> Bool {
        if lhs.points != rhs.points {
            return lhs.points > rhs.points
        }
        if lhs.goalDifference != rhs.goalDifference {
            return lhs.goalDifference > rhs.goalDifference
        }
        if lhs.goalsFor != rhs.goalsFor {
            return lhs.goalsFor > rhs.goalsFor
        }
        return lhs.won > rhs.won
    }
}

// MARK: - Fixture Generator

public struct FixtureGenerator {

    /// A league season with its real number of rounds, placed on the shared
    /// season calendar (Saturdays, then free Wednesdays). The round-robin is
    /// repeated as often as needed, venues swapping on every repeat, so the
    /// Scottish Premiership plays 38 rounds and MLS 34.
    public static func generateLeagueSeason(
        clubIds: [UUID],
        competitionName: String,
        startDateString: String,
        rounds: Int
    ) -> [Fixture] {
        var seen = Set<UUID>()
        let uniqueClubs = clubIds.filter { seen.insert($0).inserted }
        guard uniqueClubs.count >= 2, rounds >= 1 else { return [] }

        var slots: [UUID?] = uniqueClubs.map { Optional($0) }
        if !slots.count.isMultiple(of: 2) { slots.append(nil) }
        let n = slots.count

        // One full round-robin by the circle method.
        var base: [[(UUID?, UUID?)]] = []
        let stationary = slots[0]
        var rotating = Array(slots[1...])
        for round in 1...(n - 1) {
            var pairs: [(UUID?, UUID?)] = []
            for match in 0..<(n / 2) {
                if match == 0 {
                    pairs.append(round % 2 == 1 ? (stationary, rotating[0]) : (rotating[0], stationary))
                } else {
                    let a = rotating[match], b = rotating[rotating.count - match]
                    pairs.append(match % 2 == 1 ? (a, b) : (b, a))
                }
            }
            base.append(pairs)
            if let last = rotating.popLast() { rotating.insert(last, at: 0) }
        }

        // Repeat it, swapping venues on every other pass, up to `rounds`.
        var schedule: [[(UUID?, UUID?)]] = []
        var pass = 0
        while schedule.count < rounds {
            for pairs in base where schedule.count < rounds {
                schedule.append(pass.isMultiple(of: 2) ? pairs : pairs.map { ($0.1, $0.0) })
            }
            pass += 1
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let opening = formatter.date(from: startDateString) ?? Date()
        let slotNumbers = SeasonCalendar.leagueSlots(rounds: rounds)

        var fixtures: [Fixture] = []
        for (index, pairs) in schedule.enumerated() {
            let slot = slotNumbers[index]
            let date = Calendar.current.date(byAdding: .day, value: SeasonCalendar.dayOffset(forSlot: slot), to: opening) ?? opening
            let dateString = formatter.string(from: date)
            for case let (home?, away?) in pairs {
                fixtures.append(Fixture(homeClubId: home, awayClubId: away, matchWeek: slot,
                                        date: dateString, competition: competitionName))
            }
        }
        return fixtures
    }

    /// Generates a complete double round-robin schedule for a given set of club IDs.
    /// Every club plays every other club exactly once at home and once away.
    ///
    /// Leagues with an odd number of clubs are supported by adding a "bye" slot:
    /// each round one club rests, and every club still meets every other club
    /// twice. (Previously an odd league silently produced no fixtures at all, so
    /// a 23-club division never played a match.)
    public static func generateDoubleRoundRobin(
        clubIds: [UUID],
        competitionName: String,
        startDateString: String = "2024-08-10",
        skippingWeeks: Set<Int> = [],
        singleRoundRobin: Bool = false
    ) -> [Fixture] {
        // Ignore accidental duplicates so a club can never be drawn against itself.
        var seen = Set<UUID>()
        let uniqueClubs = clubIds.filter { seen.insert($0).inserted }
        guard uniqueClubs.count >= 2 else { return [] }

        // `nil` is the bye slot for odd-sized leagues.
        var slots: [UUID?] = uniqueClubs.map { Optional($0) }
        if !slots.count.isMultiple(of: 2) {
            slots.append(nil)
        }
        
        let n = slots.count
        let singleRounds = n - 1
        let matchesPerRound = n / 2
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let baseDate = dateFormatter.date(from: startDateString) ?? Date()
        let calendar = Calendar.current
        
        // League round -> calendar week, leaving reserved (cup) weeks free.
        var calendarWeeks: [Int] = []
        var candidateWeek = 1
        while calendarWeeks.count < singleRounds * (singleRoundRobin ? 1 : 2) {
            if !skippingWeeks.contains(candidateWeek) { calendarWeeks.append(candidateWeek) }
            candidateWeek += 1
        }
        func week(forRound round: Int) -> Int { calendarWeeks[round - 1] }
        
        var generatedFixtures: [Fixture] = []
        
        // Polygon (circle) method: keep slots[0] stationary, rotate slots[1..<n].
        let stationary = slots[0]
        var rotating = Array(slots[1...])
        
        // 1. First half of the season (rounds 1 to n-1).
        for round in 1...singleRounds {
            let roundDate = calendar.date(byAdding: .day, value: (week(forRound: round) - 1) * 7, to: baseDate) ?? baseDate
            let dateStr = dateFormatter.string(from: roundDate)
            
            for match in 0..<matchesPerRound {
                let first: UUID?
                let second: UUID?
                
                if match == 0 {
                    // Match against the stationary slot, alternating venue.
                    if round % 2 == 1 {
                        first = stationary
                        second = rotating[0]
                    } else {
                        first = rotating[0]
                        second = stationary
                    }
                } else {
                    let teamA = rotating[match]
                    let teamB = rotating[rotating.count - match]
                    if match % 2 == 1 {
                        first = teamA
                        second = teamB
                    } else {
                        first = teamB
                        second = teamA
                    }
                }
                
                // A pairing with the bye slot means that club rests this round.
                guard let home = first, let away = second else { continue }
                generatedFixtures.append(
                    Fixture(
                        homeClubId: home,
                        awayClubId: away,
                        matchWeek: week(forRound: round),
                        date: dateStr,
                        competition: competitionName
                    )
                )
            }
            
            // Rotate circular array (last element moves to index 0).
            if let last = rotating.popLast() {
                rotating.insert(last, at: 0)
            }
        }
        
        // Very large leagues (30 clubs) play each opponent once, as real
        // leagues of that size do, so their season fits the calendar.
        if singleRoundRobin { return generatedFixtures }

        // 2. Second half of the season (rounds n to 2*(n-1)) mirrors the first
        // half with the venues inverted.
        let firstHalf = generatedFixtures
        for round in 1...singleRounds {
            let secondHalfWeek = week(forRound: round + singleRounds)
            let roundDate = calendar.date(byAdding: .day, value: (secondHalfWeek - 1) * 7, to: baseDate) ?? baseDate
            let dateStr = dateFormatter.string(from: roundDate)
            
            for match in firstHalf where match.matchWeek == week(forRound: round) {
                generatedFixtures.append(
                    Fixture(
                        homeClubId: match.awayClubId, // Inverted
                        awayClubId: match.homeClubId, // Inverted
                        matchWeek: secondHalfWeek,
                        date: dateStr,
                        competition: competitionName
                    )
                )
            }
        }
        
        return generatedFixtures
    }
}

// MARK: - Table Zones

/// What a finishing position means for a club, used to colour league tables.
public enum TableZone: String, CaseIterable, Hashable {
    case champions
    case europe
    case promotion
    case playOff
    case relegation
    case none

    public var displayName: String {
        switch self {
        case .champions: return "Champions"
        case .europe: return "European places"
        case .promotion: return "Automatic promotion"
        case .playOff: return "Play-offs"
        case .relegation: return "Relegation"
        case .none: return ""
        }
    }
}

extension LeagueTier {
    /// The zone for a 1-based `position` in a table of `clubCount` clubs.
    /// `hasHigherTier` / `hasLowerTier` say whether promotion and relegation
    /// actually exist this season (single-division countries have neither).
    public func zone(forPosition position: Int, clubCount: Int, hasHigherTier: Bool, hasLowerTier: Bool) -> TableZone {
        guard position >= 1, position <= clubCount else { return .none }
        if hasLowerTier, position > clubCount - min(relegationCount, clubCount) {
            return .relegation
        }
        if isTopFlight {
            if position == 1 { return .champions }
            if position <= europeanSlots { return .europe }
            return .none
        }
        guard hasHigherTier else { return position == 1 ? .champions : .none }
        if position <= autoPromotionCount { return .promotion }
        if playoffPromotionCount > 0, position <= autoPromotionCount + 4 { return .playOff }
        return .none
    }
}
