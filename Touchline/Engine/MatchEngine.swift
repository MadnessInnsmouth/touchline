//
//  MatchEngine.swift
//  Touchline
//
//  Minute-by-minute match simulation.
//
//  Each minute one side has the ball. Who has it depends on the strength of
//  the two midfields (and how each side wants to play); what that side does
//  with it depends on its attack against the other side's defence. Players
//  are rated for the position they are actually playing, so a centre-back
//  up front or a winger at left-back is a real weakness. Tactics trade one
//  thing for another: going for it creates chances and leaves gaps, a low
//  block concedes shots but few good ones, a high press wins the ball high
//  and tires legs.
//
//  The match can stop at any minute (for the manager's changes, or when one
//  of the manager's players is hurt) and pick up exactly where it left off.
//  The manager's side is never changed by the engine unless the manager has
//  asked the assistant to make substitutions; an injured player who cannot
//  carry on is the one exception, and even then a live match stops first so
//  the manager can choose who comes on.
//

import Foundation

public struct MatchEngine {

    // MARK: - Match Configuration

    public struct SimulationConfig {
        public var neutralVenue: Bool
        public var matchWeek: Int
        public var competition: String
        public var date: String
        public var isKnockout: Bool
        /// 0 for an ordinary match; 1-3 for a derby of rising ferocity.
        public var derbyIntensity: Int
        /// Coaching influence on each side (1.0 = neutral; a few percent either way).
        public var homeCoachingMultiplier: Double
        public var awayCoachingMultiplier: Double
        /// The club whose manager is the user in this match. The engine never
        /// makes changes to this side on its own (see `userAutoSubs`).
        public var userClubId: UUID?
        /// Live match: stop when one of the user's players cannot carry on, so
        /// the manager picks the replacement.
        public var pauseForUserDecisions: Bool
        /// When (if ever) the assistant manager may make substitutions for
        /// the user's side.
        public var userAutoSubs: MatchSettings.AutoSubTiming
        public var userAutoSubAggression: MatchSettings.AutoSubAggression
        /// The second leg of a two-legged knockout tie: extra time and
        /// penalties follow if the sides are level on aggregate. The carries
        /// are the goals each side (as home and away tonight) scored in the
        /// first leg.
        public var isSecondLeg: Bool = false
        public var homeAggregateCarry: Int = 0
        public var awayAggregateCarry: Int = 0

        public init(
            neutralVenue: Bool = false,
            matchWeek: Int = 1,
            competition: String = "League Match",
            date: String = "2024-09-01",
            isKnockout: Bool = false,
            derbyIntensity: Int = 0,
            homeCoachingMultiplier: Double = 1.0,
            awayCoachingMultiplier: Double = 1.0,
            userClubId: UUID? = nil,
            pauseForUserDecisions: Bool = false,
            userAutoSubs: MatchSettings.AutoSubTiming = .off,
            userAutoSubAggression: MatchSettings.AutoSubAggression = .balanced
        ) {
            self.neutralVenue = neutralVenue
            self.matchWeek = matchWeek
            self.competition = competition
            self.date = date
            self.isKnockout = isKnockout
            self.derbyIntensity = max(0, min(3, derbyIntensity))
            self.homeCoachingMultiplier = max(0.9, min(1.1, homeCoachingMultiplier))
            self.awayCoachingMultiplier = max(0.9, min(1.1, awayCoachingMultiplier))
            self.userClubId = userClubId
            self.pauseForUserDecisions = pauseForUserDecisions
            self.userAutoSubs = userAutoSubs
            self.userAutoSubAggression = userAutoSubAggression
        }
    }

    // MARK: - Tuning

    /// Calibrated by simulating tens of thousands of matches: two equal sides
    /// produce about 2.6 goals, 11-12 shots, 4-5 on target, 4-5 corners and 11
    /// fouls each, with home/draw/away close to 45/25/30. A side five rating
    /// points better wins about 60% at home; a gulf of twenty still loses or
    /// draws about one match in ten.
    enum Tuning {
        static let shotBase = 0.215
        static let shotExponent = 2.4
        static let possessionExponent = 3.6
        /// Soft caps (in log space) so huge mismatches stay football, not cricket.
        static let threatCap = 0.22
        static let possessionCap = 0.9
        static let cornerPerMinute = 0.062
        static let foulPerMinute = 0.235
        static let cardPerFoul = 0.165
        static let straightRedPerFoul = 0.0018
        static let penaltyPerFoul = 0.0125
        static let directFreeKickPerFoul = 0.07
        static let offsidePerMinute = 0.042
        static let counterBase = 0.010
        static let homeAdvantage = 1.035
        static let xgMedian = 0.066
        static let xgSpread = 0.95
        static let blockRate = 0.23
        /// Chance per player per minute of something going wrong physically.
        static let injuryHazard = 0.00009
        static let maxSubs = 5
        static let maxWindows = 3
    }

    // MARK: - In-Match Player State

    struct ActiveMatchPlayer {
        var player: Player
        /// The position he is playing in this match.
        var slot: Position
        /// His ability in that position, before condition.
        var slotRating: Double
        var currentFatigue: Double = 0.0   // 0-100 during the game
        var currentRating: Double = 6.0
        var goals = 0
        var assists = 0
        var yellowCards = 0
        var isSentOff = false
        /// Matches banned for a red card (1 for a second yellow).
        var redCardBan = 0
        var isSubstitutedOut = false
        /// Went off hurt with no substitutions left: his side plays a man down.
        var leftInjured = false
        var minutesPlayed = 0
        /// Playing on through a knock: a little slower and more at risk.
        var carryingKnock = false
        /// Hurt and cannot carry on.
        var mustComeOff = false
        /// The manager has been told (live matches).
        var managerTold = false

        init(player: Player, slot: Position) {
            self.player = player
            self.slot = slot
            self.slotRating = MatchEngine.rating(of: player, in: slot)
        }

        var isOnPitch: Bool { !isSentOff && !leftInjured && !isSubstitutedOut }

        /// Ability right now: position, form, morale, fitness, sharpness,
        /// tiredness and any knock he is carrying.
        func effectiveSkill() -> Double {
            guard isOnPitch else { return 0 }
            var skill = slotRating
            let formModifier = 1.0 + ((player.averageForm - 6.5) * 0.02)
            skill *= min(1.08, max(0.92, formModifier))
            skill *= player.morale.performanceMultiplier
            let fitness = min(100.0, max(0.0, player.matchFitness))
            skill *= 0.82 + fitness / 100.0 * 0.18
            let sharpness = min(100.0, max(0.0, player.sharpness))
            skill *= 0.92 + sharpness / 100.0 * 0.08
            skill *= 1.0 - (currentFatigue / 100.0) * 0.30
            if carryingKnock { skill *= 0.90 }
            if mustComeOff { skill *= 0.55 }
            return skill
        }
    }

    /// A player's level in a given position: his overall, adjusted by how his
    /// attributes suit the role, and by how used to it he is.
    static func rating(of player: Player, in slot: Position) -> Double {
        let primary = player.primaryPosition
        if slot == primary { return Double(player.overall) }
        let attrs = player.attributes
        let shift = Double(attrs.calculateOverall(for: slot) - attrs.calculateOverall(for: primary))
        var value = Double(player.overall) + shift
        let familiarity: Double
        if player.positions.contains(slot) {
            familiarity = 0.985
        } else if slot == .GK || primary == .GK {
            familiarity = 0.75
        } else if adjacent(primary, slot) {
            familiarity = 0.95
        } else if primary.category == slot.category {
            familiarity = 0.92
        } else {
            familiarity = 0.86
        }
        value *= familiarity
        return max(15, min(Double(player.overall), value))
    }

    private static func adjacent(_ a: Position, _ b: Position) -> Bool {
        let pairs: [Set<Position>] = [
            [.LB, .LWB], [.RB, .RWB], [.LB, .CB], [.RB, .CB], [.CB, .CDM], [.CDM, .CM], [.CM, .CAM],
            [.LM, .LW], [.RM, .RW], [.LM, .LWB], [.RM, .RWB], [.CAM, .CF], [.CF, .ST], [.LW, .ST], [.RW, .ST],
            [.LM, .CM], [.RM, .CM], [.LW, .RW], [.LM, .RM], [.LB, .RB], [.LWB, .RWB], [.CAM, .LW], [.CAM, .RW]
        ]
        return pairs.contains([a, b])
    }

    // MARK: - Side State

    struct SideState {
        var active: [ActiveMatchPlayer]
        var departed: [ActiveMatchPlayer] = []
        var bench: [Player]
        var subsUsed = 0
        var subWindowsUsed = 0
        var lastSubMinute = -1
        var goals = 0
        var shots = 0
        var shotsOnTarget = 0
        var corners = 0
        var fouls = 0
        var offsides = 0
        var saves = 0
        var tackles = 0
        var xG = 0.0
        var possessionMinutes = 0.0
        var defendingMinutes = 0.0

        init(club: Club) {
            let positions = club.tactics.formation.defaultPositions
            active = club.startingXIPlayers.enumerated().map { idx, player in
                ActiveMatchPlayer(player: player, slot: idx < positions.count ? positions[idx] : player.primaryPosition)
            }
            bench = club.substitutePlayers
        }

        var onPitchCount: Int { active.filter { $0.isOnPitch }.count }

        /// Substitutions are limited in number and in "windows": changes made
        /// at the same stoppage, or at half-time, count as one.
        func canSubstitute(atMinute minute: Int, extraTime: Bool) -> Bool {
            let maxSubs = Tuning.maxSubs + (extraTime ? 1 : 0)
            let maxWindows = Tuning.maxWindows + (extraTime ? 1 : 0)
            guard subsUsed < maxSubs else { return false }
            if minute == lastSubMinute || minute == 46 { return true }
            return subWindowsUsed < maxWindows
        }

        func subsRemaining(atMinute minute: Int, extraTime: Bool) -> Int {
            guard canSubstitute(atMinute: minute, extraTime: extraTime) else { return 0 }
            return max(0, Tuning.maxSubs + (extraTime ? 1 : 0) - subsUsed)
        }

        mutating func registerSubstitution(atMinute minute: Int) {
            if minute != lastSubMinute && minute != 46 { subWindowsUsed += 1 }
            lastSubMinute = minute
            subsUsed += 1
        }

        var allPlayers: [ActiveMatchPlayer] { active + departed }
    }

    // MARK: - Public API

    /// Standard convenience signature.
    public static func simulateMatch(home: Club, away: Club, neutralVenue: Bool = false) -> MatchResult {
        var mutableHome = home
        var mutableAway = away
        let config = SimulationConfig(neutralVenue: neutralVenue)
        return simulateCore(homeClub: &mutableHome, awayClub: &mutableAway, config: config, resume: nil, pauseAfter: nil).0
    }

    /// Full match simulation returning updated club rosters (with fatigue, cards, injuries applied) and MatchResult.
    public static func simulateFullMatch(home: inout Club, away: inout Club, config: SimulationConfig) -> MatchResult {
        simulateCore(homeClub: &home, awayClub: &away, config: config, resume: nil, pauseAfter: nil).0
    }

    /// A match stopped part-way: everything the engine needs to carry on,
    /// plus the story so far.
    public struct PausedMatch {
        var home: SideState
        var away: SideState
        var events: [MatchEvent]
        var secondHalfStoppage: Int
        var maxMinute: Int
        /// The next minute to be played.
        var minute: Int
        /// The match so far: score, events and stats.
        public var snapshot: MatchResult
        /// Set when play stopped because one of the manager's players is hurt.
        public var stopReason: String?
        public var injuredUserPlayerId: UUID?

        /// The last minute played.
        public var minutePlayed: Int { max(0, minute - 1) }
        public var isExtraTime: Bool { maxMinute > 90 + secondHalfStoppage }
        public var homeOnPitch: [UUID] { home.active.map { $0.player.id } }
        public var awayOnPitch: [UUID] { away.active.map { $0.player.id } }
        public var homeBenchIds: [UUID] { home.bench.map { $0.id } }
        public var awayBenchIds: [UUID] { away.bench.map { $0.id } }
        public var homeSubsRemaining: Int { home.subsRemaining(atMinute: minute, extraTime: isExtraTime) }
        public var awaySubsRemaining: Int { away.subsRemaining(atMinute: minute, extraTime: isExtraTime) }
        public var homeWindowsRemaining: Int { max(0, Tuning.maxWindows + (isExtraTime ? 1 : 0) - home.subWindowsUsed) }
        public var awayWindowsRemaining: Int { max(0, Tuning.maxWindows + (isExtraTime ? 1 : 0) - away.subWindowsUsed) }
        /// Players who have gone off (or been sent off) and cannot return.
        public var unavailableIds: Set<UUID> {
            Set((home.departed + away.departed).map { $0.player.id })
                .union((home.active + away.active).filter { !$0.isOnPitch }.map { $0.player.id })
        }
        public var sentOffIds: Set<UUID> {
            Set((home.active + away.active).filter { $0.isSentOff }.map { $0.player.id })
        }
        /// Players hurt but still on the pitch.
        public var hurtIds: Set<UUID> {
            Set((home.active + away.active).filter { $0.isOnPitch && ($0.mustComeOff || $0.carryingKnock) }.map { $0.player.id })
        }
        /// In-match tiredness (0-100) of everyone on the pitch.
        public var fatigue: [UUID: Double] {
            var map: [UUID: Double] = [:]
            for p in home.active + away.active { map[p.player.id] = p.currentFatigue }
            return map
        }
    }

    /// Plays the first half only. Nothing is written back to the clubs yet.
    public static func playFirstHalf(home: inout Club, away: inout Club, config: SimulationConfig) -> PausedMatch? {
        simulateCore(homeClub: &home, awayClub: &away, config: config, resume: nil, pauseAfter: 45).1
    }

    /// Kicks off and stops at once (before the first minute), for a match
    /// that will be played live a few minutes at a time.
    public static func kickOff(home: inout Club, away: inout Club, config: SimulationConfig) -> PausedMatch? {
        simulateCore(homeClub: &home, awayClub: &away, config: config, resume: nil, pauseAfter: 0).1
    }

    /// Plays a paused match on to `minute` (inclusive) and stops again; or to
    /// the end, writing everything back to the clubs, when the match finishes
    /// first. The clubs' current tactics and elevens are used, so changes made
    /// while paused take effect.
    public static func play(_ paused: PausedMatch, until minute: Int?, home: inout Club, away: inout Club,
                            config: SimulationConfig) -> (MatchResult, PausedMatch?) {
        simulateCore(homeClub: &home, awayClub: &away, config: config, resume: paused, pauseAfter: minute)
    }

    /// Plays the rest of a paused match.
    public static func resume(_ paused: PausedMatch, home: inout Club, away: inout Club, config: SimulationConfig) -> MatchResult {
        simulateCore(homeClub: &home, awayClub: &away, config: config, resume: paused, pauseAfter: nil).0
    }

    // MARK: - Manager's Changes

    /// Brings the side on the pitch into line with the club's chosen eleven:
    /// bench players named in the eleven come on for those left out (while
    /// substitutions remain), and everyone takes the position of his place in
    /// the eleven, so a change of formation or a swap of positions counts.
    private static func applyLineupChanges(
        club: Club,
        side: inout SideState,
        isHome: Bool,
        minute: Int,
        extraTime: Bool,
        events: inout [MatchEvent]
    ) {
        let wanted = club.tactics.startingXI
        let onPitch = Set(side.active.map { $0.player.id })
        let gone = Set(side.departed.map { $0.player.id })
        let benchIds = Set(side.bench.map { $0.id })
        var incoming = wanted.filter { !onPitch.contains($0) && !gone.contains($0) && benchIds.contains($0) }
            .compactMap { id in side.bench.first { $0.id == id } }
        let outgoing = side.active.indices.filter {
            !wanted.contains(side.active[$0].player.id) && side.active[$0].isOnPitch
        }
        for idx in outgoing {
            guard !incoming.isEmpty, side.canSubstitute(atMinute: minute, extraTime: extraTime) else { break }
            let playerIn = incoming.removeFirst()
            let reason: SubReason = side.active[idx].mustComeOff ? .injury : .manager
            substitute(&side, outIndex: idx, incoming: playerIn, club: club, isHome: isHome,
                       minute: minute, reason: reason, events: &events)
        }
        // Everyone takes the position of his place in the chosen eleven. A
        // player who is no longer in it but still out there (sent off, or
        // with no change left to replace him) keeps the place he had.
        var arranged = [ActiveMatchPlayer?](repeating: nil, count: max(side.active.count, wanted.count))
        var leftovers: [ActiveMatchPlayer] = []
        for p in side.active {
            if let i = wanted.firstIndex(of: p.player.id), i < arranged.count, arranged[i] == nil {
                arranged[i] = p
            } else {
                leftovers.append(p)
            }
        }
        for i in arranged.indices where arranged[i] == nil && !leftovers.isEmpty {
            arranged[i] = leftovers.removeFirst()
        }
        side.active = arranged.compactMap { $0 } + leftovers
        assignSlots(&side, formation: club.tactics.formation)
    }

    /// Gives each player on the pitch the position of his place in the eleven.
    private static func assignSlots(_ side: inout SideState, formation: FormationPreset) {
        let positions = formation.defaultPositions
        for idx in side.active.indices {
            let slot = idx < positions.count ? positions[idx] : side.active[idx].player.primaryPosition
            if side.active[idx].slot != slot {
                side.active[idx].slot = slot
                side.active[idx].slotRating = rating(of: side.active[idx].player, in: slot)
            }
        }
    }

    enum SubReason { case manager, injury, fatigue, chasing, protecting, booked, poorForm, tactical }

    private static func substitute(
        _ side: inout SideState,
        outIndex: Int,
        incoming: Player,
        club: Club,
        isHome: Bool,
        minute: Int,
        reason: SubReason,
        events: inout [MatchEvent]
    ) {
        var out = side.active[outIndex]
        out.isSubstitutedOut = true
        side.departed.append(out)
        var fresh = ActiveMatchPlayer(player: incoming, slot: out.slot)
        fresh.currentRating = 6.0
        side.active[outIndex] = fresh
        side.bench.removeAll { $0.id == incoming.id }
        side.registerSubstitution(atMinute: minute)
        // An injury line names the man who replaces him.
        if reason == .injury,
           let i = events.lastIndex(where: { $0.type == .injury && $0.playerId == out.player.id }) {
            events[i].detailText += " " + Commentary.injuryReplacement(incoming: incoming, injured: out.player)
            events[i].shortText += " · \(incoming.displayName) on"
        }
        let text = Commentary.substitution(playerIn: incoming, playerOut: out.player, club: club, minute: minute, reason: reason)
        events.append(MatchEvent(minute: minute, type: .substitution, clubId: club.id, playerId: incoming.id,
                                 assistPlayerId: out.player.id, shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
    }

    // MARK: - Core Simulation Loop

    /// Whether the tie is level: on the night, or on aggregate in a second leg.
    private static func tieIsLevel(_ state: PausedMatch, config: SimulationConfig) -> Bool {
        state.home.goals + config.homeAggregateCarry == state.away.goals + config.awayAggregateCarry
    }

    private static func simulateCore(
        homeClub: inout Club,
        awayClub: inout Club,
        config: SimulationConfig,
        resume: PausedMatch?,
        pauseAfter: Int?
    ) -> (MatchResult, PausedMatch?) {
        var state: PausedMatch
        if var r = resume {
            r.stopReason = nil
            r.injuredUserPlayerId = nil
            let extra = r.isExtraTime
            // Only the manager's own side changes while the match is stopped;
            // the other side's changes are the engine's.
            if homeClub.id == config.userClubId {
                applyLineupChanges(club: homeClub, side: &r.home, isHome: true, minute: r.minute, extraTime: extra, events: &r.events)
            }
            if awayClub.id == config.userClubId {
                applyLineupChanges(club: awayClub, side: &r.away, isHome: false, minute: r.minute, extraTime: extra, events: &r.events)
            }
            state = r
        } else {
            homeClub.ensureTacticalIntegrity()
            awayClub.ensureTacticalIntegrity()
            let stoppage = Int.random(in: 2...6)
            var events: [MatchEvent] = []
            events.append(MatchEvent(
                minute: 1,
                type: .kickOff,
                shortText: config.derbyIntensity > 0
                    ? "Derby day! \(homeClub.name) vs \(awayClub.name) is underway."
                    : "Kick-off! \(homeClub.name) vs \(awayClub.name) is underway.",
                detailText: config.derbyIntensity > 0
                    ? "A ferocious atmosphere at \(homeClub.stadium) as the referee gets the derby underway. Bragging rights are on the line."
                    : "The referee blows the whistle and the match begins at \(homeClub.stadium).",
                isHomeTeam: true
            ))
            let empty = MatchResult(homeClubId: homeClub.id, awayClubId: awayClub.id, homeGoals: 0, awayGoals: 0,
                                    matchWeek: config.matchWeek, competition: config.competition, date: config.date, attendance: 0)
            state = PausedMatch(home: SideState(club: homeClub), away: SideState(club: awayClub), events: events,
                                secondHalfStoppage: stoppage, maxMinute: 90 + stoppage, minute: 1, snapshot: empty)
        }

        var minute = state.minute
        if let pauseAfter, pauseAfter < minute {
            state.snapshot = makeResult(state, homeClub: homeClub, awayClub: awayClub, config: config, motm: nil)
            return (state.snapshot, state)
        }

        while minute <= state.maxMinute {
            playMinute(minute, state: &state, homeClub: homeClub, awayClub: awayClub, config: config)

            if minute == 45 {
                let ht = Commentary.halfTimeSummary(home: homeClub, away: awayClub,
                                                    homeGoals: state.home.goals, awayGoals: state.away.goals)
                state.events.append(MatchEvent(minute: 45, type: .halfTime, shortText: ht.short, detailText: ht.detail, isHomeTeam: true))
            }

            // A knockout tie level after 90 minutes (on aggregate, in a
            // second leg) goes to extra time.
            if minute == 90 + state.secondHalfStoppage && config.isKnockout
                && tieIsLevel(state, config: config) && !state.isExtraTime {
                let aggHome = state.home.goals + config.homeAggregateCarry
                let aggAway = state.away.goals + config.awayAggregateCarry
                state.events.append(MatchEvent(
                    minute: minute,
                    type: .extraTimeStart,
                    shortText: config.isSecondLeg
                        ? "EXTRA TIME! Level at \(aggHome)-\(aggAway) on aggregate"
                        : "EXTRA TIME! Scores tied at \(state.home.goals)-\(state.away.goals)",
                    detailText: config.isSecondLeg
                        ? "Two legs could not separate these sides: \(aggHome)-\(aggAway) on aggregate. Thirty more minutes to come, and one more substitution each."
                        : "Ninety minutes could not separate these sides. Thirty more to come, and one more substitution each.",
                    isHomeTeam: true
                ))
                state.maxMinute = minute + 30
            }

            let stopForManager = minute < state.maxMinute && config.pauseForUserDecisions && state.injuredUserPlayerId != nil
            var reachedStop = false
            if let pauseAfter, minute >= pauseAfter, minute < state.maxMinute { reachedStop = true }
            if reachedStop || stopForManager {
                state.minute = minute + 1
                state.snapshot = makeResult(state, homeClub: homeClub, awayClub: awayClub, config: config, motm: nil)
                return (state.snapshot, state)
            }
            minute += 1
        }
        state.minute = minute

        // Penalty shootout if still level after extra time.
        var shootout: (Int, Int)? = nil
        if config.isKnockout && tieIsLevel(state, config: config) {
            shootout = resolvePenaltyShootout(homeClub: homeClub, awayClub: awayClub, state: &state)
        }

        // Final whistle: result-based adjustments to ratings and a little
        // individual variation.
        let finalHome = state.home.goals
        let finalAway = state.away.goals
        finaliseRatings(&state.home, goalsFor: finalHome, goalsAgainst: finalAway)
        finaliseRatings(&state.away, goalsFor: finalAway, goalsAgainst: finalHome)

        let all = state.home.allPlayers + state.away.allPlayers
        let motm = all.filter { $0.minutesPlayed >= 20 || $0.goals > 0 }.max { $0.currentRating < $1.currentRating }
        var homeGoals = state.home.goals
        var awayGoals = state.away.goals
        if let shootout {
            // Recorded as a one-goal win, as elsewhere in the game.
            if shootout.0 > shootout.1 { homeGoals += 1 } else { awayGoals += 1 }
        }
        let ft = Commentary.fullTimeSummary(home: homeClub, away: awayClub, homeGoals: homeGoals, awayGoals: awayGoals, motm: motm?.player)
        state.events.append(MatchEvent(minute: max(1, minute - 1), type: .fullTime, shortText: ft.short, detailText: ft.detail, isHomeTeam: true))

        var result = makeResult(state, homeClub: homeClub, awayClub: awayClub, config: config, motm: motm?.player.id)
        result.homeGoals = homeGoals
        result.awayGoals = awayGoals

        applyMatchToClub(club: &homeClub, players: state.home.allPlayers, opponentGoals: state.away.goals, motmId: motm?.player.id)
        applyMatchToClub(club: &awayClub, players: state.away.allPlayers, opponentGoals: state.home.goals, motmId: motm?.player.id)
        homeClub.seasonResults.append(result)
        awayClub.seasonResults.append(result)
        return (result, nil)
    }

    /// The match so far as a result: score, events, stats and ratings.
    private static func makeResult(_ state: PausedMatch, homeClub: Club, awayClub: Club, config: SimulationConfig, motm: UUID?) -> MatchResult {
        let total = state.home.possessionMinutes + state.away.possessionMinutes
        let homePoss = total == 0 ? 50.0
            : ((state.home.possessionMinutes / total) * 1000.0).rounded() / 10.0
        func stats(_ side: SideState, _ club: Club, possession: Double) -> MatchStats {
            MatchStats(
                possession: possession,
                shots: side.shots,
                shotsOnTarget: side.shotsOnTarget,
                corners: side.corners,
                fouls: side.fouls,
                offsides: side.offsides,
                passAccuracy: passAccuracy(side, tactics: club.tactics, possession: possession),
                tacklesWon: side.tackles,
                saves: side.saves,
                xG: (side.xG * 100).rounded() / 100
            )
        }
        var ratings: [UUID: Double] = [:]
        for p in state.home.allPlayers + state.away.allPlayers {
            ratings[p.player.id] = (min(10, max(3, p.currentRating)) * 10).rounded() / 10
        }
        return MatchResult(
            homeClubId: homeClub.id, awayClubId: awayClub.id,
            homeGoals: state.home.goals, awayGoals: state.away.goals,
            events: state.events, matchWeek: config.matchWeek, competition: config.competition, date: config.date,
            attendance: homeClub.finances.expectedAttendance(opponentReputation: awayClub.reputation),
            homeStats: stats(state.home, homeClub, possession: homePoss),
            awayStats: stats(state.away, awayClub, possession: ((100.0 - homePoss) * 10).rounded() / 10),
            playerRatings: ratings,
            manOfTheMatch: motm
        )
    }

    /// Pass completion follows the passers and the style: short passing keeps
    /// it tidy, long balls go astray, and the side with the ball passes better.
    private static func passAccuracy(_ side: SideState, tactics: Tactics, possession: Double) -> Double {
        let outfield = side.active.filter { $0.slot != .GK && $0.minutesPlayed > 0 }
        guard !outfield.isEmpty else { return 0 }
        let passing = outfield.reduce(0.0) { $0 + Double($1.player.attributes.passing) } / Double(outfield.count)
        var value = 70.0 + (passing - 60.0) * 0.45
        switch tactics.passingStyle {
        case .short: value += 4
        case .mixed: break
        case .long: value -= 8
        case .direct: value -= 6
        }
        value += (possession - 50.0) * 0.25
        // A fixed figure per match so it does not flicker while paused.
        return (min(93.0, max(58.0, value)) * 10).rounded() / 10
    }

    // MARK: - One Minute of Football

    /// How a side is set up this minute, after the manager's (or for the AI,
    /// the game state's) tactics.
    private struct Setup {
        var attack: Double      // creating chances
        var midfield: Double    // keeping the ball
        var defence: Double     // stopping chances
        var keeper: Double
        var mentality: Int      // 0 defensive ... 4 all-out attack
        var tactics: Tactics
        var pace: Double        // of the forwards, for counter-attacks
    }

    private static func setup(_ side: SideState, club: Club, isHome: Bool, config: SimulationConfig,
                              minute: Int, goalDiff: Int, isUserSide: Bool) -> Setup {
        let coaching = isHome ? config.homeCoachingMultiplier : config.awayCoachingMultiplier
        let venue = (isHome && !config.neutralVenue) ? Tuning.homeAdvantage : 1.0
        let boost = coaching * venue

        var defSum = 0.0, defW = 0.0, midSum = 0.0, midW = 0.0, attSum = 0.0, attW = 0.0
        var allSum = 0.0, allN = 0.0
        var keeper = 30.0
        var defenders = 0.0, midfielders = 0.0, forwards = 0.0
        var paceSum = 0.0, paceN = 0.0
        for p in side.active where p.isOnPitch {
            let skill = p.effectiveSkill() * boost
            switch p.slot {
            case .GK:
                keeper = skill
            case .CB, .LB, .RB, .LWB, .RWB:
                defSum += skill; defW += 1; defenders += 1
                if p.slot == .LWB || p.slot == .RWB { midSum += skill * 0.4; midW += 0.4; attSum += skill * 0.2; attW += 0.2 }
            case .CDM:
                midSum += skill; midW += 1; defSum += skill * 0.5; defW += 0.5; midfielders += 1; defenders += 0.4
            case .CM:
                midSum += skill; midW += 1; midfielders += 1
                attSum += skill * 0.3; attW += 0.3
            case .CAM:
                midSum += skill * 0.7; midW += 0.7; attSum += skill * 0.7; attW += 0.7; midfielders += 0.7; forwards += 0.4
            case .LM, .RM:
                midSum += skill * 0.8; midW += 0.8; attSum += skill * 0.5; attW += 0.5; midfielders += 0.8; forwards += 0.2
            case .LW, .RW:
                attSum += skill; attW += 1; midSum += skill * 0.3; midW += 0.3; forwards += 0.8
                paceSum += Double(p.player.attributes.pace); paceN += 1
            case .ST, .CF:
                attSum += skill; attW += 1; forwards += 1
                paceSum += Double(p.player.attributes.pace); paceN += 1
            }
            if p.slot != .GK { allSum += skill; allN += 1 }
        }
        let all = allN > 0 ? allSum / allN : 30
        var defence = defW > 0 ? defSum / defW : all * 0.8
        var midfield = midW > 0 ? midSum / midW : all * 0.8
        var attack = attW > 0 ? attSum / attW : all * 0.8
        // Numbers in each line matter as well as quality.
        defence *= 1.0 + 0.035 * (defenders - 4.4)
        midfield *= 1.0 + 0.035 * (midfielders - 3.6)
        attack *= 1.0 + 0.045 * (forwards - 2.0)
        // A man down hurts everywhere, most of all in keeping the ball.
        let numbers = Double(side.onPitchCount) / 11.0
        defence *= pow(numbers, 0.9)
        midfield *= pow(numbers, 1.3)
        attack *= pow(numbers, 1.1)

        // An AI side manages the game: chasing it late, sitting on a lead.
        // The user's side plays exactly as the manager set it up.
        var mentality = mentalityIndex(club.tactics.mentality)
        if !isUserSide {
            if goalDiff < 0 && minute >= 82 { mentality += 2 }
            else if goalDiff < 0 && minute >= 65 { mentality += 1 }
            else if goalDiff >= 2 && minute >= 60 { mentality -= 1 }
            else if goalDiff == 1 && minute >= 78 { mentality -= 1 }
            mentality = max(0, min(4, mentality))
        }
        return Setup(attack: attack, midfield: midfield, defence: defence, keeper: keeper, mentality: mentality,
                     tactics: club.tactics, pace: paceN > 0 ? paceSum / paceN : 60)
    }

    private static func mentalityIndex(_ m: Mentality) -> Int {
        switch m {
        case .defensive: return 0
        case .cautious: return 1
        case .balanced: return 2
        case .attacking: return 3
        case .allOutAttack: return 4
        }
    }

    /// (chances made, chances conceded, exposure to counter-attacks)
    private static let mentalityEffects: [(make: Double, concede: Double, exposure: Double)] = [
        (0.72, 0.80, 0.45), (0.86, 0.90, 0.72), (1.0, 1.0, 1.0), (1.13, 1.10, 1.35), (1.27, 1.24, 1.8)
    ]

    private static func softCap(_ ratio: Double, _ cap: Double) -> Double {
        exp(cap * tanh(log(max(0.01, ratio)) / cap))
    }

    private static func playMinute(_ minute: Int, state: inout PausedMatch, homeClub: Club, awayClub: Club, config: SimulationConfig) {
        let userIsHome = homeClub.id == config.userClubId
        let userIsAway = awayClub.id == config.userClubId

        // Legs tire.
        updateFatigue(&state.home, tactics: homeClub.tactics)
        updateFatigue(&state.away, tactics: awayClub.tactics)

        // Injuries that cannot wait, and substitutions.
        handleForcedChanges(&state, homeClub: homeClub, awayClub: awayClub, minute: minute, config: config)
        let extraTime = state.isExtraTime
        let homeGoalsNow = state.home.goals
        let awayGoalsNow = state.away.goals
        if !userIsHome || autoSubsAllowed(config, minute: minute) {
            aiSubstitutions(&state.home, opponentGoals: awayGoalsNow, club: homeClub, isHome: true, minute: minute,
                            extraTime: extraTime, aggression: userIsHome ? config.userAutoSubAggression : .balanced,
                            events: &state.events)
        }
        if !userIsAway || autoSubsAllowed(config, minute: minute) {
            aiSubstitutions(&state.away, opponentGoals: homeGoalsNow, club: awayClub, isHome: false, minute: minute,
                            extraTime: extraTime, aggression: userIsAway ? config.userAutoSubAggression : .balanced,
                            events: &state.events)
        }

        let home = setup(state.home, club: homeClub, isHome: true, config: config, minute: minute,
                         goalDiff: state.home.goals - state.away.goals, isUserSide: userIsHome)
        let away = setup(state.away, club: awayClub, isHome: false, config: config, minute: minute,
                         goalDiff: state.away.goals - state.home.goals, isUserSide: userIsAway)

        // Who has the ball.
        func possessionStrength(_ s: Setup) -> Double {
            var v = s.midfield * s.tactics.passingStyle.possessionMultiplier
            switch s.tactics.pressing { case .low: v *= 0.95; case .medium: break; case .high: v *= 1.04 }
            switch s.tactics.tempo { case .slow: v *= 1.03; case .normal: break; case .fast: v *= 0.97 }
            v *= 1.0 + 0.01 * Double(s.mentality - 2)   // attacking sides commit more men forward on the ball
            return max(1, v)
        }
        let ratio = pow(possessionStrength(home) / possessionStrength(away), Tuning.possessionExponent)
        let logit = Tuning.possessionCap * tanh(log(ratio) / Tuning.possessionCap)
        let homeShare = min(0.72, max(0.28, 1.0 / (1.0 + exp(-logit))))
        let homeHasBall = Double.random(in: 0..<1) < homeShare
        if homeHasBall {
            state.home.possessionMinutes += 1; state.away.defendingMinutes += 1
        } else {
            state.away.possessionMinutes += 1; state.home.defendingMinutes += 1
        }

        let margin = abs(state.home.goals - state.away.goals)
        let marginModifier: Double = margin >= 4 ? 0.5 : margin == 3 ? 0.62 : margin == 2 ? 0.8 : 1.0

        if homeHasBall {
            attackingMinute(attackerIsHome: true, att: home, def: away, state: &state, homeClub: homeClub, awayClub: awayClub,
                            minute: minute, config: config, marginModifier: marginModifier)
        } else {
            attackingMinute(attackerIsHome: false, att: away, def: home, state: &state, homeClub: homeClub, awayClub: awayClub,
                            minute: minute, config: config, marginModifier: marginModifier)
        }

        // Knocks and strains.
        checkInjuries(&state.home, club: homeClub, isHome: true, minute: minute, config: config, events: &state.events)
        checkInjuries(&state.away, club: awayClub, isHome: false, minute: minute, config: config, events: &state.events)

        // A late lead brings out the time-wasting (and the odd booking for it).
        if minute >= 75 && margin >= 1 && Double.random(in: 0..<1) < 0.004 {
            if state.home.goals > state.away.goals {
                bookForTimeWasting(&state.home, club: homeClub, isHome: true, minute: minute, events: &state.events)
            } else {
                bookForTimeWasting(&state.away, club: awayClub, isHome: false, minute: minute, events: &state.events)
            }
        }

        // Did the manager's player just get hurt? Stop for him (live matches).
        if config.pauseForUserDecisions {
            let userSide: SideState? = userIsHome ? state.home : (userIsAway ? state.away : nil)
            if let side = userSide, let hurt = side.active.first(where: { $0.isOnPitch && $0.mustComeOff && !$0.managerTold }) {
                state.injuredUserPlayerId = hurt.player.id
                state.stopReason = "\(hurt.player.fullName) can't carry on. Choose who replaces him."
                if userIsHome {
                    if let i = state.home.active.firstIndex(where: { $0.player.id == hurt.player.id }) { state.home.active[i].managerTold = true }
                } else if let i = state.away.active.firstIndex(where: { $0.player.id == hurt.player.id }) {
                    state.away.active[i].managerTold = true
                }
            }
        }
    }

    private static func autoSubsAllowed(_ config: SimulationConfig, minute: Int) -> Bool {
        switch config.userAutoSubs {
        case .off: return false
        case .halfTime: return minute == 46
        case .secondHalf: return minute >= 60
        case .throughout: return minute >= 46
        }
    }

    private static func attackingMinute(
        attackerIsHome: Bool,
        att: Setup,
        def: Setup,
        state: inout PausedMatch,
        homeClub: Club,
        awayClub: Club,
        minute: Int,
        config: SimulationConfig,
        marginModifier: Double
    ) {
        let attTactics = att.tactics
        let defTactics = def.tactics
        let attM = mentalityEffects[att.mentality]
        let defM = mentalityEffects[def.mentality]

        let threat = att.attack * 0.6 + att.midfield * 0.4
        let resist = def.defence * 0.7 + def.midfield * 0.3
        let r = softCap(threat / max(1, resist), Tuning.threatCap)

        // Tactical shape of the attack and of the defence.
        var shotMod = 1.0, xgShift = 0.0, cornerMod = 1.0, offsideMod = 1.0
        switch attTactics.tempo {
        case .fast: shotMod *= 1.10; xgShift -= 0.05; offsideMod *= 1.2
        case .normal: break
        case .slow: shotMod *= 0.88; xgShift += 0.06; offsideMod *= 0.8
        }
        switch attTactics.width {
        case .wide: shotMod *= 1.04; cornerMod *= 1.25; xgShift -= 0.04
        case .normal: break
        case .narrow: shotMod *= 0.97; cornerMod *= 0.8; xgShift += 0.04
        }
        switch attTactics.passingStyle {
        case .short: shotMod *= 0.95; xgShift += 0.08
        case .mixed: break
        case .long: shotMod *= 1.03; xgShift -= 0.10; cornerMod *= 1.1
        case .direct: shotMod *= 1.08; xgShift -= 0.05; offsideMod *= 1.25
        }
        switch defTactics.pressing {
        case .low: shotMod *= 1.06; xgShift -= 0.12; offsideMod *= 0.7
        case .medium: break
        case .high: shotMod *= 0.93; xgShift += 0.12; offsideMod *= 1.35
        }
        switch defTactics.width {
        case .wide: shotMod *= 1.04
        case .normal: break
        case .narrow: shotMod *= 0.95; cornerMod *= 1.1
        }

        let pShot = Tuning.shotBase * pow(r, Tuning.shotExponent) * attM.make * defM.concede * shotMod * marginModifier
        if Double.random(in: 0..<1) < pShot {
            openPlayShot(attackerIsHome: attackerIsHome, ratio: r, xgShift: xgShift, isCounter: false,
                         state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute, keeper: def.keeper)
        } else {
            // Possession won back: a little credit to a defender or midfielder.
            if attackerIsHome { creditDefensiveAction(&state.away) } else { creditDefensiveAction(&state.home) }
        }

        // Corners from pressure.
        if Double.random(in: 0..<1) < Tuning.cornerPerMinute * cornerMod {
            corner(attackerIsHome: attackerIsHome, state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute,
                   keeper: def.keeper)
        }

        if Double.random(in: 0..<1) < Tuning.offsidePerMinute * offsideMod {
            if attackerIsHome { state.home.offsides += 1 } else { state.away.offsides += 1 }
            // Some offsides are worth a line of commentary.
            let side = attackerIsHome ? state.home : state.away
            if Double.random(in: 0..<1) < 0.3,
               let runner = side.active.filter({ $0.isOnPitch && $0.slot.category != .goalkeeper && $0.slot.category != .defender }).randomElement() {
                let club = attackerIsHome ? homeClub : awayClub
                state.events.append(MatchEvent(minute: minute, type: .commentary, clubId: club.id, playerId: runner.player.id,
                                               shortText: "Offside: \(runner.player.displayName) \(minute)'",
                                               detailText: CommentaryLines.offside(attacker: runner.player, club: club).randomElement()!,
                                               isHomeTeam: attackerIsHome))
            }
        }

        // Counter-attack: a side committed forward leaves space behind.
        var counter = Tuning.counterBase * attM.exposure
        counter *= pow(max(40, def.pace) / 70.0, 2)
        if def.mentality <= 1 { counter *= 1.2 }
        if defTactics.passingStyle == .direct { counter *= 1.2 }
        if defTactics.pressing == .low { counter *= 1.1 }
        if Double.random(in: 0..<1) < counter * marginModifier {
            let counterRatio = softCap((def.attack * 0.7 + def.midfield * 0.3) / max(1, att.defence * 0.8 + att.midfield * 0.2), Tuning.threatCap)
            openPlayShot(attackerIsHome: !attackerIsHome, ratio: counterRatio, xgShift: 0.45, isCounter: true,
                         state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute, keeper: att.keeper)
        }

        // Fouls by the side without the ball.
        var foulChance = Tuning.foulPerMinute
        switch defTactics.pressing { case .low: foulChance *= 0.85; case .medium: break; case .high: foulChance *= 1.15 }
        foulChance += Double(config.derbyIntensity) * 0.03
        if Double.random(in: 0..<1) < foulChance {
            foul(defendingIsHome: !attackerIsHome, state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute,
                 keeper: def.keeper, config: config)
        }
    }

    private static func creditDefensiveAction(_ side: inout SideState) {
        guard Double.random(in: 0..<1) < 0.36 else { return }
        side.tackles += 1
        let candidates = side.active.indices.filter {
            side.active[$0].isOnPitch && [.defender, .midfielder].contains(side.active[$0].slot.category)
        }
        guard let idx = candidates.randomElement() else { return }
        side.active[idx].currentRating += 0.03
    }

    // MARK: Shots

    /// Weighted by position and finishing: strikers take most of the shots,
    /// midfielders some, defenders few, the goalkeeper none.
    private static func pickShooter(_ side: SideState, header: Bool = false, excluding excluded: Int? = nil) -> Int? {
        let candidates = side.active.indices.filter { $0 != excluded && side.active[$0].isOnPitch && side.active[$0].slot != .GK }
        guard !candidates.isEmpty else { return nil }
        func weight(_ p: ActiveMatchPlayer) -> Double {
            let positionWeight: Double
            switch p.slot {
            case .ST, .CF: positionWeight = 5
            case .LW, .RW, .CAM: positionWeight = 3
            case .LM, .RM, .CM: positionWeight = 1.5
            case .CDM: positionWeight = 0.7
            case .LWB, .RWB: positionWeight = 0.6
            case .CB: positionWeight = header ? 2.5 : 0.35
            case .LB, .RB: positionWeight = 0.4
            case .GK: positionWeight = 0
            }
            let skill = header
                ? Double(p.player.attributes.heading + p.player.attributes.jumping) / 140.0
                : Double(p.player.attributes.shooting + p.player.attributes.offTheBall) / 140.0
            return positionWeight * pow(max(0.3, skill), 2) * (1 - p.currentFatigue / 250)
        }
        let weights = candidates.map { weight(side.active[$0]) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates.randomElement() }
        var roll = Double.random(in: 0..<total)
        for (i, w) in zip(candidates, weights) {
            roll -= w
            if roll < 0 { return i }
        }
        return candidates.last
    }

    private static func pickCreator(_ side: SideState, excluding shooter: Int) -> Int? {
        let candidates = side.active.indices.filter { $0 != shooter && side.active[$0].isOnPitch && side.active[$0].slot != .GK }
        guard !candidates.isEmpty else { return nil }
        func weight(_ p: ActiveMatchPlayer) -> Double {
            let positionWeight: Double
            switch p.slot {
            case .CAM, .LW, .RW: positionWeight = 3
            case .LM, .RM, .CM, .LWB, .RWB: positionWeight = 2
            case .ST, .CF: positionWeight = 1.5
            case .LB, .RB, .CDM: positionWeight = 1
            case .CB: positionWeight = 0.3
            case .GK: positionWeight = 0
            }
            let skill = Double(p.player.attributes.passing + p.player.attributes.vision + p.player.attributes.crossing) / 210.0
            return positionWeight * pow(max(0.3, skill), 2)
        }
        let weights = candidates.map { weight(side.active[$0]) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates.randomElement() }
        var roll = Double.random(in: 0..<total)
        for (i, w) in zip(candidates, weights) {
            roll -= w
            if roll < 0 { return i }
        }
        return candidates.last
    }

    private static func gaussian() -> Double {
        let u = max(1e-9, Double.random(in: 0..<1))
        let v = Double.random(in: 0..<1)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }

    private static func keeperIndex(_ side: SideState) -> Int? {
        side.active.firstIndex { $0.isOnPitch && $0.slot == .GK } ?? side.active.firstIndex { $0.isOnPitch }
    }

    private static func openPlayShot(
        attackerIsHome: Bool,
        ratio: Double,
        xgShift: Double,
        isCounter: Bool,
        state: inout PausedMatch,
        homeClub: Club,
        awayClub: Club,
        minute: Int,
        keeper: Double
    ) {
        let attackingClub = attackerIsHome ? homeClub : awayClub
        let defendingClub = attackerIsHome ? awayClub : homeClub
        var attSide = attackerIsHome ? state.home : state.away
        var defSide = attackerIsHome ? state.away : state.home
        defer {
            if attackerIsHome { state.home = attSide; state.away = defSide } else { state.away = attSide; state.home = defSide }
        }
        guard let shooterIdx = pickShooter(attSide) else { return }
        let creatorIdx = Double.random(in: 0..<1) < 0.78 ? pickCreator(attSide, excluding: shooterIdx) : nil
        let shooter = attSide.active[shooterIdx].player

        var xg = exp(log(Tuning.xgMedian) + 0.9 * log(ratio) + xgShift + gaussian() * Tuning.xgSpread)
        // Defenders and deep midfielders mostly shoot from distance.
        if [.defender, .midfielder].contains(attSide.active[shooterIdx].slot.category) && attSide.active[shooterIdx].slot != .CAM {
            xg *= 0.7
        }
        xg = min(0.75, max(0.01, xg))
        attSide.shots += 1
        attSide.xG += xg
        attSide.active[shooterIdx].currentRating += 0.05
        if let c = creatorIdx { attSide.active[c].currentRating += 0.06 }

        // Blocked by a defender.
        let blockRate = Tuning.blockRate * (isCounter ? 0.5 : 1.0)
        if Double.random(in: 0..<1) < blockRate {
            if let blocker = defSide.active.indices.filter({ defSide.active[$0].isOnPitch && defSide.active[$0].slot.category == .defender }).randomElement() {
                defSide.active[blocker].currentRating += 0.12
            }
            if Double.random(in: 0..<1) < 0.4 {
                attSide.corners += 1
            }
            if xg > 0.15 {
                let text = Commentary.blockedShot(shooter: shooter, club: attackingClub, defending: defendingClub, minute: minute)
                state.events.append(MatchEvent(minute: minute, type: .chance, clubId: attackingClub.id, playerId: shooter.id,
                                               shortText: text.short, detailText: text.detail, isHomeTeam: attackerIsHome))
            }
            return
        }

        let finishing = Double(shooter.attributes.shooting) * 0.6 + Double(shooter.attributes.composure) * 0.4
        let finish = min(1.3, max(0.7, 1.0 + (finishing - 65.0) * 0.01))
        let keeperFactor = min(1.3, max(0.72, 1.0 - (keeper - 65.0) * 0.01))
        let pGoal = min(0.95, xg / (1.0 - blockRate) * finish * keeperFactor)
        let gkIdx = keeperIndex(defSide)

        if Double.random(in: 0..<1) < pGoal {
            // VAR: now and then the goal is ruled out (offside, handball, a
            // foul in the build-up).
            if Double.random(in: 0..<1) < 0.05 {
                attSide.shots -= 1
                attSide.xG -= xg
                attSide.active[shooterIdx].currentRating -= 0.05
                if let c = creatorIdx { attSide.active[c].currentRating -= 0.06 }
                let line = CommentaryLines.varGoalDisallowed(scorer: shooter, club: attackingClub).randomElement()!
                state.events.append(MatchEvent(minute: minute, type: .varDecision, clubId: attackingClub.id, playerId: shooter.id,
                                               shortText: "VAR: \(shooter.displayName)'s goal disallowed \(minute)'",
                                               detailText: line, isHomeTeam: attackerIsHome))
                return
            }
            attSide.goals += 1
            attSide.shotsOnTarget += 1
            attSide.active[shooterIdx].goals += 1
            attSide.active[shooterIdx].currentRating += 1.0
            var assister: Player? = nil
            if let c = creatorIdx {
                attSide.active[c].assists += 1
                attSide.active[c].currentRating += 0.6
                assister = attSide.active[c].player
            }
            concede(&defSide, keeperIdx: gkIdx)
            let homeGoals = attackerIsHome ? attSide.goals : defSide.goals
            let awayGoals = attackerIsHome ? defSide.goals : attSide.goals
            let text = Commentary.goal(scorer: shooter, assister: assister, club: attackingClub, opponent: defendingClub,
                                       minute: minute, homeGoals: homeGoals, awayGoals: awayGoals, isHome: attackerIsHome,
                                       goalType: isCounter ? .counterAttackBreakaway : nil)
            state.events.append(MatchEvent(minute: minute, type: .goal, clubId: attackingClub.id, playerId: shooter.id,
                                           assistPlayerId: assister?.id, shortText: text.short, detailText: text.detail,
                                           isHomeTeam: attackerIsHome))
            if Double.random(in: 0..<1) < 0.12 {
                state.events.append(MatchEvent(minute: minute, type: .varDecision, clubId: attackingClub.id, playerId: shooter.id,
                                               shortText: "VAR check: goal stands \(minute)'",
                                               detailText: CommentaryLines.varGoalStands(scorer: shooter).randomElement()!,
                                               isHomeTeam: attackerIsHome))
            }
            return
        }

        if Double.random(in: 0..<1) < 0.36 * finish {
            // On target, saved.
            attSide.shotsOnTarget += 1
            attSide.active[shooterIdx].currentRating += 0.08
            defSide.saves += 1
            if let g = gkIdx {
                defSide.active[g].currentRating += xg > 0.25 ? 0.45 : 0.18
            }
            if Double.random(in: 0..<1) < 0.3 { attSide.corners += 1 }
            if xg > 0.12 || Double.random(in: 0..<1) < 0.35 {
                let keeperPlayer = gkIdx.map { defSide.active[$0].player } ?? shooter
                let text = Commentary.save(keeper: keeperPlayer, shooter: shooter, keeperClub: defendingClub, minute: minute,
                                           isHome: !attackerIsHome, quality: xg)
                state.events.append(MatchEvent(minute: minute, type: .shotOnTarget, clubId: attackingClub.id, playerId: shooter.id,
                                               shortText: text.short, detailText: text.detail, isHomeTeam: attackerIsHome))
            }
            return
        }

        // Off target.
        let woodwork = Double.random(in: 0..<1) < 0.05
        if xg > 0.3 { attSide.active[shooterIdx].currentRating -= 0.25 }
        if woodwork || xg > 0.12 || Double.random(in: 0..<1) < 0.25 {
            let text = Commentary.miss(shooter: shooter, club: attackingClub, minute: minute, isWoodwork: woodwork, quality: xg)
            state.events.append(MatchEvent(minute: minute, type: woodwork ? .woodwork : .chanceMissed, clubId: attackingClub.id,
                                           playerId: shooter.id, shortText: text.short, detailText: text.detail,
                                           isHomeTeam: attackerIsHome))
        }
    }

    /// A goal against: the keeper and the back line take the blame.
    private static func concede(_ side: inout SideState, keeperIdx: Int?) {
        if let g = keeperIdx { side.active[g].currentRating -= 0.3 }
        for i in side.active.indices where side.active[i].isOnPitch {
            switch side.active[i].slot.category {
            case .defender: side.active[i].currentRating -= 0.2
            case .midfielder where side.active[i].slot == .CDM: side.active[i].currentRating -= 0.1
            default: break
            }
        }
    }

    // MARK: Set Pieces

    private static func corner(attackerIsHome: Bool, state: inout PausedMatch, homeClub: Club, awayClub: Club, minute: Int, keeper: Double) {
        let attackingClub = attackerIsHome ? homeClub : awayClub
        let defendingClub = attackerIsHome ? awayClub : homeClub
        var attSide = attackerIsHome ? state.home : state.away
        var defSide = attackerIsHome ? state.away : state.home
        defer {
            if attackerIsHome { state.home = attSide; state.away = defSide } else { state.away = attSide; state.home = defSide }
        }
        attSide.corners += 1
        let onPitch = attSide.active.indices.filter { attSide.active[$0].isOnPitch }
        guard let takerIdx = onPitch.first(where: { attSide.active[$0].player.id == attackingClub.tactics.cornerTaker })
                ?? onPitch.max(by: { attSide.active[$0].player.attributes.crossing < attSide.active[$1].player.attributes.crossing }) else { return }
        // Most corners come to nothing; about three in ten produce a shot.
        guard Double.random(in: 0..<1) < 0.30, let headerIdx = pickShooter(attSide, header: true, excluding: takerIdx) else {
            if Double.random(in: 0..<1) < 0.3 {
                let taker = attSide.active[takerIdx].player
                state.events.append(MatchEvent(minute: minute, type: .corner, clubId: attackingClub.id, playerId: taker.id,
                                               shortText: "Corner: \(attackingClub.name) \(minute)'",
                                               detailText: CommentaryLines.cornerCleared(taker: taker, defending: defendingClub).randomElement()!,
                                               isHomeTeam: attackerIsHome))
            }
            return
        }
        let taker = attSide.active[takerIdx].player
        let target = attSide.active[headerIdx].player
        let delivery = Double(taker.attributes.crossing) / 70.0
        let aerial = Double(target.attributes.heading + target.attributes.jumping) / 140.0
        var defAerial = 0.0, n = 0.0
        for p in defSide.active where p.isOnPitch && p.slot.category == .defender {
            defAerial += Double(p.player.attributes.heading + p.player.attributes.jumping) / 140.0; n += 1
        }
        let defenders = n > 0 ? defAerial / n : 0.65
        let xg = min(0.45, max(0.02, 0.07 * delivery * aerial / max(0.4, defenders) * exp(gaussian() * 0.6)))
        attSide.shots += 1
        attSide.xG += xg
        let keeperFactor = min(1.25, max(0.75, 1.0 - (keeper - 65.0) * 0.008))
        if Double.random(in: 0..<1) < xg * keeperFactor {
            attSide.goals += 1
            attSide.shotsOnTarget += 1
            attSide.active[headerIdx].goals += 1
            attSide.active[headerIdx].currentRating += 1.0
            attSide.active[takerIdx].assists += 1
            attSide.active[takerIdx].currentRating += 0.6
            concede(&defSide, keeperIdx: keeperIndex(defSide))
            let text = Commentary.goal(scorer: target, assister: taker, club: attackingClub, opponent: defendingClub, minute: minute,
                                       homeGoals: attackerIsHome ? attSide.goals : defSide.goals,
                                       awayGoals: attackerIsHome ? defSide.goals : attSide.goals,
                                       isHome: attackerIsHome, goalType: .glancingCornerHeader)
            state.events.append(MatchEvent(minute: minute, type: .goal, clubId: attackingClub.id, playerId: target.id,
                                           assistPlayerId: taker.id, shortText: text.short, detailText: text.detail, isHomeTeam: attackerIsHome))
        } else if Double.random(in: 0..<1) < 0.3 {
            attSide.shotsOnTarget += 1
            defSide.saves += 1
            if let g = keeperIndex(defSide) { defSide.active[g].currentRating += 0.15 }
        }
    }

    private static func directFreeKick(attackerIsHome: Bool, state: inout PausedMatch, homeClub: Club, awayClub: Club, minute: Int, keeper: Double) {
        let attackingClub = attackerIsHome ? homeClub : awayClub
        let defendingClub = attackerIsHome ? awayClub : homeClub
        var attSide = attackerIsHome ? state.home : state.away
        var defSide = attackerIsHome ? state.away : state.home
        defer {
            if attackerIsHome { state.home = attSide; state.away = defSide } else { state.away = attSide; state.home = defSide }
        }
        let onPitch = attSide.active.indices.filter { attSide.active[$0].isOnPitch && attSide.active[$0].slot != .GK }
        guard let takerIdx = onPitch.first(where: { attSide.active[$0].player.id == attackingClub.tactics.freeKickTaker })
                ?? onPitch.max(by: { attSide.active[$0].player.attributes.freeKicks < attSide.active[$1].player.attributes.freeKicks }) else { return }
        let taker = attSide.active[takerIdx].player
        let xg = min(0.12, max(0.02, 0.06 * Double(taker.attributes.freeKicks) / 70.0))
        attSide.shots += 1
        attSide.xG += xg
        let keeperFactor = min(1.25, max(0.75, 1.0 - (keeper - 65.0) * 0.008))
        if Double.random(in: 0..<1) < xg * keeperFactor {
            attSide.goals += 1
            attSide.shotsOnTarget += 1
            attSide.active[takerIdx].goals += 1
            attSide.active[takerIdx].currentRating += 1.2
            concede(&defSide, keeperIdx: keeperIndex(defSide))
            let text = Commentary.goal(scorer: taker, assister: nil, club: attackingClub, opponent: defendingClub, minute: minute,
                                       homeGoals: attackerIsHome ? attSide.goals : defSide.goals,
                                       awayGoals: attackerIsHome ? defSide.goals : attSide.goals,
                                       isHome: attackerIsHome, goalType: .curlingFreeKick)
            state.events.append(MatchEvent(minute: minute, type: .goal, clubId: attackingClub.id, playerId: taker.id,
                                           shortText: text.short, detailText: text.detail, isHomeTeam: attackerIsHome))
        } else if Double.random(in: 0..<1) < 0.33 {
            attSide.shotsOnTarget += 1
            defSide.saves += 1
            if let g = keeperIndex(defSide) { defSide.active[g].currentRating += 0.15 }
            let text = Commentary.freeKickSaved(taker: taker, club: attackingClub, minute: minute)
            state.events.append(MatchEvent(minute: minute, type: .freeKick, clubId: attackingClub.id, playerId: taker.id,
                                           shortText: text.short, detailText: text.detail, isHomeTeam: attackerIsHome))
        }
    }

    // MARK: Fouls, Cards & Penalties

    private static func foul(defendingIsHome: Bool, state: inout PausedMatch, homeClub: Club, awayClub: Club, minute: Int,
                             keeper: Double, config: SimulationConfig) {
        let foulingClub = defendingIsHome ? homeClub : awayClub
        var side = defendingIsHome ? state.home : state.away
        side.fouls += 1
        // Who commits it: defenders and holding midfielders, the aggressive more so.
        let candidates = side.active.indices.filter { side.active[$0].isOnPitch }
        guard !candidates.isEmpty else { return }
        func weight(_ p: ActiveMatchPlayer) -> Double {
            let positionWeight: Double
            switch p.slot.category {
            case .defender: positionWeight = 1.3
            case .midfielder: positionWeight = p.slot == .CDM ? 1.6 : 1.0
            case .forward: positionWeight = 0.7
            case .goalkeeper: positionWeight = 0.05
            }
            let booked = p.yellowCards > 0 ? 0.6 : 1.0
            return positionWeight * booked * (0.6 + Double(p.player.attributes.aggression) / 100.0)
        }
        let weights = candidates.map { weight(side.active[$0]) }
        var roll = Double.random(in: 0..<max(0.001, weights.reduce(0, +)))
        var foulerIdx = candidates[0]
        for (i, w) in zip(candidates, weights) {
            roll -= w
            if roll < 0 { foulerIdx = i; break }
        }
        let fouler = side.active[foulerIdx]
        side.active[foulerIdx].currentRating -= 0.05

        // The man fouled: an outfield player of the other side.
        let otherSide = defendingIsHome ? state.away : state.home
        let victimIdx = otherSide.active.indices
            .filter { otherSide.active[$0].isOnPitch && otherSide.active[$0].slot != .GK }
            .randomElement()
        let victim = victimIdx.map { otherSide.active[$0].player }

        // Some fouls hurt the man fouled.
        if Double.random(in: 0..<1) < 0.005 + Double(config.derbyIntensity) * 0.002 {
            var victimSide = defendingIsHome ? state.away : state.home
            if let v = victimIdx, v < victimSide.active.count, victimSide.active[v].isOnPitch {
                injure(&victimSide, index: v, club: defendingIsHome ? awayClub : homeClub, isHome: !defendingIsHome,
                       minute: minute, contact: true, events: &state.events)
                if defendingIsHome { state.away = victimSide } else { state.home = victimSide }
            }
        }

        // Where it happened.
        let roll2 = Double.random(in: 0..<1)
        let isPenalty = roll2 < Tuning.penaltyPerFoul
        let isDangerousFreeKick = !isPenalty && roll2 < Tuning.penaltyPerFoul + Tuning.directFreeKickPerFoul

        // The referee's decision.
        let aggression = Double(fouler.player.attributes.aggression)
        let tackling = Double(fouler.player.attributes.tackling)
        var cardChance = Tuning.cardPerFoul * (0.55 + aggression / 110.0) * (1.25 - tackling / 200.0)
        if fouler.yellowCards > 0 { cardChance *= 0.55 }   // a booked man is careful
        if isPenalty { cardChance += 0.25 }
        cardChance += Double(config.derbyIntensity) * 0.03
        let straightRed = Double.random(in: 0..<1) < Tuning.straightRedPerFoul * (isPenalty ? 4 : 1) * (0.6 + aggression / 100.0)

        if straightRed {
            sendOff(&side, index: foulerIdx, club: foulingClub, isHome: defendingIsHome, minute: minute, secondYellow: false,
                    ban: isPenalty ? 1 : (Double.random(in: 0..<1) < 0.6 ? 3 : 1), victim: victim, events: &state.events)
        } else if Double.random(in: 0..<1) < cardChance {
            book(&side, index: foulerIdx, club: foulingClub, isHome: defendingIsHome, minute: minute, victim: victim, events: &state.events)
        } else if !isPenalty && Double.random(in: 0..<1) < 0.5 {
            // An ordinary foul: a line of commentary, not every time.
            let text = Commentary.foul(player: fouler.player, victim: victim, club: foulingClub, minute: minute)
            state.events.append(MatchEvent(minute: minute, type: .commentary, clubId: foulingClub.id, playerId: fouler.player.id,
                                           shortText: text.short, detailText: text.detail, isHomeTeam: defendingIsHome))
        }
        if defendingIsHome { state.home = side } else { state.away = side }

        if isPenalty {
            // VAR looks at most penalties: some are overturned, some confirmed.
            let roll = Double.random(in: 0..<1)
            let kickers = defendingIsHome ? awayClub : homeClub
            if roll < 0.15 {
                state.events.append(MatchEvent(minute: minute, type: .varDecision, clubId: kickers.id, playerId: victim?.id,
                                               shortText: "VAR: penalty overturned \(minute)'",
                                               detailText: CommentaryLines.varPenaltyOverturned(victim: victim, club: foulingClub).randomElement()!,
                                               isHomeTeam: !defendingIsHome))
            } else {
                if roll < 0.4 {
                    state.events.append(MatchEvent(minute: minute, type: .varDecision, clubId: kickers.id, playerId: victim?.id,
                                                   shortText: "VAR: penalty confirmed \(minute)'",
                                                   detailText: CommentaryLines.varPenaltyConfirmed(victim: victim).randomElement()!,
                                                   isHomeTeam: !defendingIsHome))
                }
                penalty(kickerIsHome: !defendingIsHome, state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute)
            }
        } else if isDangerousFreeKick {
            directFreeKick(attackerIsHome: !defendingIsHome, state: &state, homeClub: homeClub, awayClub: awayClub, minute: minute, keeper: keeper)
        }
    }

    private static func book(_ side: inout SideState, index: Int, club: Club, isHome: Bool, minute: Int, victim: Player? = nil,
                             events: inout [MatchEvent]) {
        let player = side.active[index].player
        if side.active[index].yellowCards >= 1 {
            side.active[index].yellowCards += 1
            sendOff(&side, index: index, club: club, isHome: isHome, minute: minute, secondYellow: true, ban: 1, victim: victim,
                    events: &events)
            return
        }
        side.active[index].yellowCards = 1
        side.active[index].currentRating -= 0.3
        let text = Commentary.card(player: player, club: club, isRed: false, minute: minute, victim: victim)
        events.append(MatchEvent(minute: minute, type: .yellowCard, clubId: club.id, playerId: player.id,
                                 shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
    }

    private static func sendOff(_ side: inout SideState, index: Int, club: Club, isHome: Bool, minute: Int, secondYellow: Bool,
                                ban: Int, victim: Player? = nil, events: inout [MatchEvent]) {
        let player = side.active[index].player
        side.active[index].isSentOff = true
        side.active[index].redCardBan = ban
        side.active[index].currentRating -= secondYellow ? 1.2 : 1.5
        let text = Commentary.card(player: player, club: club, isRed: !secondYellow, isSecondYellow: secondYellow, minute: minute,
                                   victim: victim)
        events.append(MatchEvent(minute: minute, type: secondYellow ? .secondYellow : .redCard, clubId: club.id, playerId: player.id,
                                 shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
        if !secondYellow && Double.random(in: 0..<1) < 0.35 {
            events.append(MatchEvent(minute: minute, type: .varDecision, clubId: club.id, playerId: player.id,
                                     shortText: "VAR: red card confirmed \(minute)'",
                                     detailText: CommentaryLines.varRedConfirmed(player: player).randomElement()!,
                                     isHomeTeam: isHome))
        }
    }

    private static func bookForTimeWasting(_ side: inout SideState, club: Club, isHome: Bool, minute: Int, events: inout [MatchEvent]) {
        let candidates = side.active.indices.filter { side.active[$0].isOnPitch && side.active[$0].yellowCards == 0 }
        guard let idx = candidates.first(where: { side.active[$0].slot == .GK }) ?? candidates.randomElement() else { return }
        let player = side.active[idx].player
        side.active[idx].yellowCards = 1
        side.active[idx].currentRating -= 0.2
        let text = Commentary.timeWastingBooking(player: player, club: club, minute: minute)
        events.append(MatchEvent(minute: minute, type: .yellowCard, clubId: club.id, playerId: player.id,
                                 shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
    }

    private static func penalty(kickerIsHome: Bool, state: inout PausedMatch, homeClub: Club, awayClub: Club, minute: Int) {
        let kickingClub = kickerIsHome ? homeClub : awayClub
        let defendingClub = kickerIsHome ? awayClub : homeClub
        var attSide = kickerIsHome ? state.home : state.away
        var defSide = kickerIsHome ? state.away : state.home
        defer {
            if kickerIsHome { state.home = attSide; state.away = defSide } else { state.away = attSide; state.home = defSide }
        }
        let onPitch = attSide.active.indices.filter { attSide.active[$0].isOnPitch && attSide.active[$0].slot != .GK }
        guard let takerIdx = onPitch.first(where: { attSide.active[$0].player.id == kickingClub.tactics.penaltyTaker })
                ?? onPitch.max(by: { attSide.active[$0].player.attributes.penalties < attSide.active[$1].player.attributes.penalties }),
              let gkIdx = keeperIndex(defSide) else { return }
        let taker = attSide.active[takerIdx].player
        let gk = defSide.active[gkIdx].player
        attSide.shots += 1
        attSide.xG += 0.76
        let skill = Double(taker.attributes.penalties + taker.attributes.composure)
        let keeping = Double(gk.attributes.oneOnOnes + gk.attributes.reflexes)
        let conversion = min(0.90, max(0.60, 0.76 + (skill - keeping) * 0.0015))
        if Double.random(in: 0..<1) < conversion {
            attSide.goals += 1
            attSide.shotsOnTarget += 1
            attSide.active[takerIdx].goals += 1
            attSide.active[takerIdx].currentRating += 0.8
            concede(&defSide, keeperIdx: gkIdx)
            let text = Commentary.goal(scorer: taker, assister: nil, club: kickingClub, opponent: defendingClub, minute: minute,
                                       homeGoals: kickerIsHome ? attSide.goals : defSide.goals,
                                       awayGoals: kickerIsHome ? defSide.goals : attSide.goals,
                                       isHome: kickerIsHome, goalType: .clinicalPenalty)
            state.events.append(MatchEvent(minute: minute, type: .goal, clubId: kickingClub.id, playerId: taker.id,
                                           shortText: text.short, detailText: text.detail, isHomeTeam: kickerIsHome))
        } else {
            let saved = Double.random(in: 0..<1) < 0.7
            attSide.active[takerIdx].currentRating -= 0.8
            if saved {
                attSide.shotsOnTarget += 1
                defSide.saves += 1
                defSide.active[gkIdx].currentRating += 0.9
            }
            let shortText = saved ? "PENALTY SAVED! \(gk.displayName) denies \(taker.displayName)! \(minute)'"
                                  : "PENALTY MISSED! \(taker.displayName) puts it wide! \(minute)'"
            let detail = saved
                ? CommentaryLines.penaltySaved(taker: taker, keeper: gk).randomElement()!
                : CommentaryLines.penaltyMissed(taker: taker, club: kickingClub).randomElement()! + " A huge let-off for \(defendingClub.name)."
            state.events.append(MatchEvent(minute: minute, type: .penaltyMissed, clubId: kickingClub.id, playerId: taker.id,
                                           shortText: shortText, detailText: detail, isHomeTeam: kickerIsHome))
        }
    }

    // MARK: - Penalty Shootout

    /// Returns the shootout score (home, away).
    private static func resolvePenaltyShootout(homeClub: Club, awayClub: Club, state: inout PausedMatch) -> (Int, Int) {
        state.events.append(MatchEvent(minute: state.maxMinute, type: .penaltyShootout, shortText: "PENALTY SHOOTOUT BEGINS!",
                                       detailText: "All square after extra time! The tie will be decided from twelve yards.", isHomeTeam: true))
        func takers(_ side: SideState) -> [Player] {
            let on = side.active.filter { $0.isOnPitch }.map { $0.player }
            // The keeper goes last; the best penalty takers first.
            return on.sorted { a, b in
                if (a.primaryPosition == .GK) != (b.primaryPosition == .GK) { return b.primaryPosition == .GK }
                return a.attributes.penalties + a.attributes.composure > b.attributes.penalties + b.attributes.composure
            }
        }
        let homeTakers = takers(state.home)
        let awayTakers = takers(state.away)
        guard !homeTakers.isEmpty, !awayTakers.isEmpty else { return Bool.random() ? (1, 0) : (0, 1) }
        let homeGk = keeperIndex(state.home).map { state.home.active[$0].player }
        let awayGk = keeperIndex(state.away).map { state.away.active[$0].player }
        func chance(_ taker: Player, _ keeper: Player?) -> Double {
            let k = keeper.map { Double($0.attributes.reflexes + $0.attributes.oneOnOnes) } ?? 100
            return min(0.92, max(0.55, 0.75 + (Double(taker.attributes.penalties + taker.attributes.composure) - k) * 0.0015))
        }
        var h = 0, a = 0
        var round = 1
        while round <= 30 {
            if Double.random(in: 0..<1) < chance(homeTakers[(round - 1) % homeTakers.count], awayGk) { h += 1 }
            if round <= 5 && h > a + (6 - round) { break }
            if Double.random(in: 0..<1) < chance(awayTakers[(round - 1) % awayTakers.count], homeGk) { a += 1 }
            if round >= 5 {
                if h != a { break }
            } else if abs(h - a) > 5 - round {
                break
            }
            round += 1
        }
        if h == a { if Bool.random() { h += 1 } else { a += 1 } }
        let homeWin = h > a
        let winner = homeWin ? homeClub : awayClub
        state.events.append(MatchEvent(minute: state.maxMinute, type: .penaltyShootout,
                                       shortText: "\(winner.name) win on penalties (\(max(h, a))-\(min(h, a)))!",
                                       detailText: homeWin ? "Jubilation for \(homeClub.name) as they prevail in the shootout!"
                                                           : "Heroics from the spot! \(awayClub.name) go through!",
                                       isHomeTeam: homeWin))
        return (h, a)
    }

    // MARK: - Fatigue

    private static func updateFatigue(_ side: inout SideState, tactics: Tactics) {
        var drain = tactics.pressing.staminaDrainMultiplier
        switch tactics.tempo { case .fast: drain *= 1.08; case .normal: break; case .slow: drain *= 0.94 }
        for idx in side.active.indices where side.active[idx].isOnPitch {
            side.active[idx].minutesPlayed += 1
            let stamina = Double(side.active[idx].player.attributes.stamina)
            // A keeper barely tires.
            let positionDrain = side.active[idx].slot == .GK ? 0.3 : 1.0
            // Arriving short of match fitness, a player tires sooner.
            let fitness = side.active[idx].player.matchFitness
            let fitnessDrain = 1.0 + max(0, 85 - fitness) / 100.0
            let perMinute = max(0.08, 0.56 - stamina * 0.0031) * drain * positionDrain * fitnessDrain
            side.active[idx].currentFatigue = min(100.0, side.active[idx].currentFatigue + perMinute)
        }
    }

    // MARK: - Injuries

    /// Each player on the pitch, each minute: fitness, tiredness, age and his
    /// own body (some players break down more than others) set the risk.
    private static func checkInjuries(_ side: inout SideState, club: Club, isHome: Bool, minute: Int, config: SimulationConfig,
                                      events: inout [MatchEvent]) {
        for idx in side.active.indices where side.active[idx].isOnPitch && !side.active[idx].mustComeOff {
            let risk = InjuryEngine.matchInjuryRisk(player: side.active[idx].player,
                                                    fatigue: side.active[idx].currentFatigue,
                                                    minute: minute,
                                                    pressing: club.tactics.pressing,
                                                    carryingKnock: side.active[idx].carryingKnock)
            if Double.random(in: 0..<1) < Tuning.injuryHazard * risk {
                injure(&side, index: idx, club: club, isHome: isHome, minute: minute, contact: false, events: &events)
            }
        }
    }

    private static func injure(_ side: inout SideState, index: Int, club: Club, isHome: Bool, minute: Int, contact: Bool,
                               events: inout [MatchEvent]) {
        let outcome = InjuryEngine.matchInjury(player: side.active[index].player, contact: contact)
        let player = side.active[index].player
        switch outcome {
        case .knock:
            // Treated on the pitch and carries on, a bit slower.
            if side.active[index].carryingKnock { return }
            side.active[index].carryingKnock = true
            side.active[index].currentFatigue = min(100, side.active[index].currentFatigue + 8)
            let text = Commentary.knock(player: player, club: club, minute: minute)
            events.append(MatchEvent(minute: minute, type: .commentary, clubId: club.id, playerId: player.id,
                                     shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
        case .playsOn(let injury):
            // Hurt, but tries to run it off. He is worse for it and can be taken off.
            side.active[index].player.injury = injury
            side.active[index].carryingKnock = true
            let text = Commentary.playingThroughInjury(player: player, club: club, minute: minute)
            events.append(MatchEvent(minute: minute, type: .injury, clubId: club.id, playerId: player.id,
                                     shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
        case .forcedOff(let injury):
            side.active[index].player.injury = injury
            side.active[index].mustComeOff = true
            let text = Commentary.injury(player: player, club: club, minute: minute, injuryType: injury.type)
            events.append(MatchEvent(minute: minute, type: .injury, clubId: club.id, playerId: player.id,
                                     shortText: text.short, detailText: text.detail, isHomeTeam: isHome))
        }
    }

    /// Players who cannot carry on are replaced, unless they belong to the
    /// manager and a live match will stop for him to choose (he gets one
    /// minute's stop; if he does nothing, the physio's call stands).
    private static func handleForcedChanges(_ state: inout PausedMatch, homeClub: Club, awayClub: Club, minute: Int, config: SimulationConfig) {
        for isHome in [true, false] {
            var side = isHome ? state.home : state.away
            let club = isHome ? homeClub : awayClub
            let isUser = club.id == config.userClubId
            for idx in side.active.indices where side.active[idx].isOnPitch && side.active[idx].mustComeOff {
                if isUser && config.pauseForUserDecisions && !side.active[idx].managerTold { continue }
                if side.canSubstitute(atMinute: minute, extraTime: state.isExtraTime),
                   let benchIdx = bestReplacement(for: side.active[idx].slot, bench: side.bench) {
                    let incoming = side.bench[benchIdx]
                    substitute(&side, outIndex: idx, incoming: incoming, club: club, isHome: isHome, minute: minute,
                               reason: .injury, events: &state.events)
                } else {
                    // No changes left: down to ten.
                    side.active[idx].leftInjured = true
                    let player = side.active[idx].player
                    state.events.append(MatchEvent(
                        minute: minute, type: .commentary, clubId: club.id, playerId: player.id,
                        shortText: "\(club.name) down to \(side.onPitchCount) men",
                        detailText: "\(player.fullName) cannot continue and \(club.name) have no changes left. They will have to see it out a man light.",
                        isHomeTeam: isHome))
                    // An outfield player takes the gloves if the keeper went off.
                    if side.active[idx].slot == .GK,
                       let stand = side.active.indices.filter({ side.active[$0].isOnPitch }).max(by: {
                           side.active[$0].player.attributes.calculateOverall(for: .GK) < side.active[$1].player.attributes.calculateOverall(for: .GK)
                       }) {
                        let oldSlot = side.active[stand].slot
                        side.active[stand].slot = .GK
                        side.active[stand].slotRating = rating(of: side.active[stand].player, in: .GK)
                        side.active[idx].slot = oldSlot
                    }
                }
            }
            if isHome { state.home = side } else { state.away = side }
        }
    }

    /// The bench player best suited to a position.
    private static func bestReplacement(for slot: Position, bench: [Player]) -> Int? {
        guard !bench.isEmpty else { return nil }
        let candidates = bench.indices.filter { slot == .GK ? bench[$0].primaryPosition == .GK : bench[$0].primaryPosition != .GK }
        let pool = candidates.isEmpty ? Array(bench.indices) : candidates
        return pool.max { rating(of: bench[$0], in: slot) < rating(of: bench[$1], in: slot) }
    }

    // MARK: - AI Substitutions

    /// How a computer manager (or the user's assistant, when allowed) uses
    /// the bench: tired legs, a booked defender on the edge, a player having a
    /// shocker, and the game state: an extra forward when chasing it, an extra
    /// defender to see out a lead. Changes come in two or three windows, as
    /// real managers make them.
    private static func aiSubstitutions(
        _ side: inout SideState,
        opponentGoals: Int,
        club: Club,
        isHome: Bool,
        minute: Int,
        extraTime: Bool,
        aggression: MatchSettings.AutoSubAggression,
        events: inout [MatchEvent]
    ) {
        guard minute >= 46, !side.bench.isEmpty, side.canSubstitute(atMinute: minute, extraTime: extraTime) else { return }
        // Decision points: rarely at the break, mostly from the hour.
        let decideNow: Bool
        if minute == 46 { decideNow = Double.random(in: 0..<1) < (side.goals < opponentGoals ? 0.35 : 0.12) }
        else if minute < 55 { decideNow = Double.random(in: 0..<1) < 0.02 }
        else if minute <= 88 { decideNow = Double.random(in: 0..<1) < 0.10 }
        else { decideNow = false }
        guard decideNow else { return }

        let goalDiff = side.goals - opponentGoals
        let threshold = aggression.fatigueThreshold
        var changesThisWindow = 0
        let maxThisWindow = minute >= 75 ? 3 : 2
        let subsCap = min(aggression.maxSubs + (extraTime ? 1 : 0), Tuning.maxSubs + (extraTime ? 1 : 0))

        while changesThisWindow < maxThisWindow, side.subsUsed < subsCap,
              side.canSubstitute(atMinute: minute, extraTime: extraTime), !side.bench.isEmpty {
            // Who should come off, and why.
            var best: (idx: Int, score: Double, reason: SubReason)? = nil
            for idx in side.active.indices where side.active[idx].isOnPitch && side.active[idx].slot != .GK {
                let p = side.active[idx]
                var score = (p.currentFatigue - threshold) / 10.0
                var reason: SubReason = .fatigue
                if p.carryingKnock { score += 1.2 }
                if p.yellowCards > 0 && p.slot.category != .forward && minute >= 55 {
                    score += 0.7
                    if score > 0.6 { reason = .booked }
                }
                if p.currentRating < 5.8 && minute >= 55 {
                    score += 0.6 + (5.8 - p.currentRating)
                    reason = .poorForm
                }
                if goalDiff < 0 && minute >= 60 && (p.slot.category == .defender || p.slot == .CDM) {
                    score += 0.9
                    reason = .chasing
                }
                if goalDiff > 0 && minute >= 72 && p.slot.category == .forward {
                    score += 0.8
                    reason = .protecting
                }
                score += max(0, Double(minute - 55) / 30.0)   // fresh legs as the game wears on
                if score > (best?.score ?? 0.9) { best = (idx, score, reason) }
            }
            guard let choice = best else { break }
            // Who comes on.
            let outSlot = side.active[choice.idx].slot
            let benchIdx: Int?
            switch choice.reason {
            case .chasing:
                benchIdx = side.bench.indices.filter { side.bench[$0].primaryPosition.isAttacking }
                    .max { side.bench[$0].overall < side.bench[$1].overall } ?? bestReplacement(for: outSlot, bench: side.bench)
            case .protecting:
                benchIdx = side.bench.indices.filter { side.bench[$0].primaryPosition.category == .defender || side.bench[$0].primaryPosition == .CDM }
                    .max { side.bench[$0].overall < side.bench[$1].overall } ?? bestReplacement(for: outSlot, bench: side.bench)
            default:
                benchIdx = bestReplacement(for: outSlot, bench: side.bench)
            }
            guard let b = benchIdx else { break }
            let incoming = side.bench[b]
            // Not worth it if the replacement is much worse, unless he is spent.
            let current = side.active[choice.idx].effectiveSkill()
            let replacement = rating(of: incoming, in: outSlot)
            if replacement < current * 0.85 && choice.reason != .chasing && choice.reason != .protecting && choice.score < 2.5 { break }
            substitute(&side, outIndex: choice.idx, incoming: incoming, club: club, isHome: isHome,
                       minute: minute, reason: choice.reason, events: &events)
            // A tactical change reshapes the side: the newcomer plays his own
            // position (an extra striker, an extra centre-back).
            if choice.reason == .chasing || choice.reason == .protecting {
                side.active[choice.idx].slot = incoming.primaryPosition
                side.active[choice.idx].slotRating = Double(incoming.overall)
            }
            changesThisWindow += 1
        }
    }

    // MARK: - Ratings

    private static func finaliseRatings(_ side: inout SideState, goalsFor: Int, goalsAgainst: Int) {
        let resultBonus = goalsFor > goalsAgainst ? 0.25 : (goalsFor < goalsAgainst ? -0.25 : 0)
        func adjust(_ p: inout ActiveMatchPlayer) {
            guard p.minutesPlayed > 0 else { return }
            var r = p.currentRating + resultBonus + gaussian() * 0.3
            if goalsAgainst == 0 && p.minutesPlayed >= 60 {
                if p.slot == .GK { r += 0.6 } else if p.slot.category == .defender { r += 0.4 }
            }
            // A short cameo stays close to average.
            if p.minutesPlayed < 20 { r = 6.0 + (r - 6.0) * 0.5 }
            p.currentRating = min(10.0, max(3.0, r))
        }
        for i in side.active.indices { adjust(&side.active[i]) }
        for i in side.departed.indices { adjust(&side.departed[i]) }
    }

    // MARK: - Post-Match Club State Synchronization

    private static func applyMatchToClub(club: inout Club, players: [ActiveMatchPlayer], opponentGoals: Int, motmId: UUID?) {
        for ap in players {
            guard var p = club.player(withId: ap.player.id) else { continue }
            p.recordMatch(
                rating: (min(10, max(3, ap.currentRating)) * 10).rounded() / 10,
                minutes: ap.minutesPlayed,
                goals: ap.goals,
                assists: ap.assists,
                yellowCard: ap.yellowCards == 1 && !ap.isSentOff,
                redCard: ap.isSentOff,
                cleanSheet: opponentGoals == 0 && ap.minutesPlayed >= 60,
                // A keeper is charged with the goals let in while he played
                // (all of them over a full match; a share for a part).
                goalsConceded: ap.slot == .GK
                    ? Int((Double(opponentGoals) * min(1.0, Double(ap.minutesPlayed) / 90.0)).rounded())
                    : 0,
                isMotm: p.id == motmId,
                redCardBan: ap.redCardBan,
                matchFatigue: ap.currentFatigue
            )
            if let inj = ap.player.injury {
                p.injury = inj
            }
            club.updatePlayer(p)
        }
    }
}
