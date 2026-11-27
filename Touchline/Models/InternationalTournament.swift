//
//  InternationalTournament.swift
//  Touchline
//
//  International tournaments contested by national teams: the FIFA World Cup
//  plus the continental championships (EURO, Copa América, AFCON, Asian Cup).
//  Modelled as a group stage followed by a single-elimination knockout bracket.
//

import Foundation

public enum InternationalTournament {

    public enum Kind: String, Codable, CaseIterable, Identifiable, Hashable {
        case worldCup
        case euro
        case copaAmerica
        case africaCupOfNations
        case asianCup

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .worldCup: return "FIFA World Cup"
            case .euro: return "UEFA European Championship"
            case .copaAmerica: return "Copa América"
            case .africaCupOfNations: return "Africa Cup of Nations"
            case .asianCup: return "AFC Asian Cup"
            }
        }

        public var shortName: String {
            switch self {
            case .worldCup: return "World Cup"
            case .euro: return "EURO"
            case .copaAmerica: return "Copa América"
            case .africaCupOfNations: return "AFCON"
            case .asianCup: return "Asian Cup"
            }
        }

        /// Confederation whose members contest this tournament (nil = whole world).
        public var confederation: Confederation? {
            switch self {
            case .worldCup: return nil
            case .euro: return .uefa
            case .copaAmerica: return .conmebol
            case .africaCupOfNations: return .caf
            case .asianCup: return .afc
            }
        }

        /// Field size (number of nations).
        public var teamCount: Int {
            switch self {
            case .worldCup: return 48
            case .euro: return 24
            case .copaAmerica: return 16
            case .africaCupOfNations: return 24
            case .asianCup: return 24
            }
        }

        /// Confederations whose members play. Copa América invites CONCACAF
        /// nations to fill the field, as the real tournament does.
        public var confederations: [Confederation] {
            switch self {
            case .worldCup: return []
            case .euro: return [.uefa]
            case .copaAmerica: return [.conmebol, .concacaf]
            case .africaCupOfNations: return [.caf]
            case .asianCup: return [.afc]
            }
        }

        /// The edition (and its opening day) that kicks off in the season
        /// starting in August of the given year, if there is one. Seasons run
        /// August to May, so the summer tournaments of the following year
        /// belong to the season before them.
        ///
        ///   World Cup        every four years (2030, 2034 ...), June to July
        ///   EURO, Copa       every four years (2028, 2032 ...), June to July
        ///   AFCON            every second year (December 2027, 2029 ...)
        ///   Asian Cup        every four years (January 2027, 2031 ...)
        public func edition(inSeasonStarting seasonStart: Int) -> (edition: Int, date: String)? {
            let summer = seasonStart + 1
            switch self {
            case .worldCup:
                return summer % 4 == 2 ? (summer, "\(summer)-06-11") : nil
            case .euro:
                return summer % 4 == 0 ? (summer, "\(summer)-06-14") : nil
            case .copaAmerica:
                return summer % 4 == 0 ? (summer, "\(summer)-06-20") : nil
            case .africaCupOfNations:
                return seasonStart % 2 == 1 ? (seasonStart, "\(seasonStart)-12-21") : nil
            case .asianCup:
                return summer % 4 == 3 ? (summer, "\(summer)-01-12") : nil
            }
        }

        /// The next edition at or after the season starting in the given year.
        public func nextEdition(fromSeasonStarting seasonStart: Int) -> (edition: Int, date: String)? {
            for year in seasonStart..<(seasonStart + 9) {
                if let slot = edition(inSeasonStarting: year) { return slot }
            }
            return nil
        }

        /// Group games played on one day.
        public var groupGamesPerDay: Int {
            switch self {
            case .worldCup: return 4
            case .copaAmerica: return 2
            default: return 3
            }
        }

        /// Teams per group.
        public var groupSize: Int { 4 }

        public var groupCount: Int { teamCount / groupSize }
    }

    // MARK: - Group row

    public struct GroupRow: Codable, Identifiable, Hashable {
        public var id: String { teamId }
        public var teamId: String
        public var played: Int
        public var won: Int
        public var drawn: Int
        public var lost: Int
        public var goalsFor: Int
        public var goalsAgainst: Int
        public var goalDifference: Int { goalsFor - goalsAgainst }
        public var points: Int

        public init(teamId: String) {
            self.teamId = teamId
            played = 0; won = 0; drawn = 0; lost = 0
            goalsFor = 0; goalsAgainst = 0; points = 0
        }

        public mutating func record(goalsFor gf: Int, goalsAgainst ga: Int) {
            played += 1
            goalsFor += gf
            goalsAgainst += ga
            if gf > ga { won += 1; points += 3 }
            else if gf == ga { drawn += 1; points += 1 }
            else { lost += 1 }
        }

        public static func sort(_ a: GroupRow, _ b: GroupRow) -> Bool {
            if a.points != b.points { return a.points > b.points }
            if a.goalDifference != b.goalDifference { return a.goalDifference > b.goalDifference }
            if a.goalsFor != b.goalsFor { return a.goalsFor > b.goalsFor }
            return a.won > b.won
        }
    }

    // MARK: - Fixture

    public struct Fixture: Codable, Identifiable, Hashable {
        public var id: UUID
        public var homeTeamId: String
        public var awayTeamId: String
        public var stage: String        // "Group A" … "Round of 16", "Final"
        public var isPlayed: Bool
        public var homeGoals: Int
        public var awayGoals: Int
        public var shootout: PenaltyShootout? = nil
        /// The day it is played (yyyy-MM-dd). Nil in older saves.
        public var date: String?

        public init(
            id: UUID = UUID(),
            homeTeamId: String,
            awayTeamId: String,
            stage: String,
            isPlayed: Bool = false,
            homeGoals: Int = 0,
            awayGoals: Int = 0,
            date: String? = nil
        ) {
            self.date = date
            self.id = id
            self.homeTeamId = homeTeamId
            self.awayTeamId = awayTeamId
            self.stage = stage
            self.isPlayed = isPlayed
            self.homeGoals = homeGoals
            self.awayGoals = awayGoals
        }
    }

    // MARK: - Tournament state

    public struct State: Codable, Identifiable, Hashable {
        public var id: UUID
        public var kind: Kind
        public var stage: Stage
        public var participantIds: [String]
        public var groupAssignments: [String: [String]]   // groupId -> teamIds
        public var fixtures: [Fixture]
        public var championId: String?
        /// Calendar year the edition is named for (nil in older saves).
        public var edition: Int?
        /// Opening day, yyyy-MM-dd.
        public var startDate: String?
        public var kickoffAnnounced: Bool?

        public var title: String {
            edition.map { "\(kind.displayName) \($0)" } ?? kind.displayName
        }

        public var endDate: String? { fixtures.compactMap { $0.date }.max() }

        public enum Stage: String, Codable, Hashable {
            case groupStage
            case knockout
            case complete
        }

        public init(
            id: UUID = UUID(),
            kind: Kind,
            stage: Stage = .groupStage,
            participantIds: [String] = [],
            groupAssignments: [String: [String]] = [:],
            fixtures: [Fixture] = [],
            championId: String? = nil,
            edition: Int? = nil,
            startDate: String? = nil
        ) {
            self.edition = edition
            self.startDate = startDate
            self.id = id
            self.kind = kind
            self.stage = stage
            self.participantIds = participantIds
            self.groupAssignments = groupAssignments
            self.fixtures = fixtures
            self.championId = championId
        }

        /// Ordered group names, e.g. ["Group A", "Group B", …].
        public var groupNames: [String] {
            groupAssignments.keys.sorted()
        }

        /// Computes the table for a given group.
        public func table(forGroup group: String) -> [GroupRow] {
            guard let teamIds = groupAssignments[group] else { return [] }
            var rows: [String: GroupRow] = [:]
            for id in teamIds { rows[id] = GroupRow(teamId: id) }
            for f in fixtures where f.stage == group {
                guard f.isPlayed else { continue }
                rows[f.homeTeamId]?.record(goalsFor: f.homeGoals, goalsAgainst: f.awayGoals)
                rows[f.awayTeamId]?.record(goalsFor: f.awayGoals, goalsAgainst: f.homeGoals)
            }
            return rows.values.sorted(by: GroupRow.sort)
        }

        public var groupStageComplete: Bool {
            let groupFixtures = fixtures.filter { $0.stage.hasPrefix("Group ") }
            return !groupFixtures.isEmpty && groupFixtures.allSatisfy { $0.isPlayed }
        }

        /// Number of qualifiers that contest the knockout bracket. The bracket
        /// always uses a power-of-two field (4, 8 or 16) so every round can be
        /// completed without byes.
        private var knockoutFieldSize: Int {
            let available = groupQualifiers().count
            if available >= 32 { return 32 }
            if available >= 16 { return 16 }
            if available >= 8 { return 8 }
            if available >= 4 { return 4 }
            return 0
        }

        /// The knockout round currently in progress, if any.
        public var activeKnockoutRound: String? {
            let rounds: [String]
            switch knockoutFieldSize {
            case 32...:
                rounds = ["Round of 32"] + Self.knockoutOrder
            case 16...:
                rounds = Self.knockoutOrder
            case 8:
                rounds = ["Quarter-Final", "Semi-Final", "Third Place", "Final"]
            case 4:
                rounds = ["Semi-Final", "Third Place", "Final"]
            default:
                rounds = []
            }

            for round in rounds {
                let roundFixtures = fixtures.filter { $0.stage == round }
                if roundFixtures.isEmpty { return round }
                if !roundFixtures.allSatisfy({ $0.isPlayed }) { return round }
            }
            return nil
        }

        public var currentRoundComplete: Bool {
            guard let round = activeKnockoutRound else { return false }
            let fixturesForRound = fixtures.filter { $0.stage == round }
            return !fixturesForRound.isEmpty && fixturesForRound.allSatisfy { $0.isPlayed }
        }

        static let knockoutOrder = ["Round of 16", "Quarter-Final", "Semi-Final", "Third Place", "Final"]

        /// Plays every fixture dated on or before `date` (earliest first),
        /// moving on to the next stage as each one finishes, until nothing more
        /// is due. Fixtures without a date (older saves) are played at once.
        ///
        /// Fixtures of `holdingTeam` (the nation the user manages) are left for
        /// the user to play.
        public mutating func play(through date: String, holdingTeam: String? = nil,
                                  simulate: (String, String) -> (Int, Int)) {
            var progressed = true
            var passes = 0
            while progressed && passes < 12 {
                passes += 1
                progressed = false
                let due = fixtures.indices
                    .filter { !fixtures[$0].isPlayed && (fixtures[$0].date ?? "") <= date }
                    .filter { holdingTeam == nil || (fixtures[$0].homeTeamId != holdingTeam && fixtures[$0].awayTeamId != holdingTeam) }
                    .sorted { (fixtures[$0].date ?? "") < (fixtures[$1].date ?? "") }
                for idx in due {
                    let (hg, ag) = simulate(fixtures[idx].homeTeamId, fixtures[idx].awayTeamId)
                    fixtures[idx].homeGoals = hg
                    fixtures[idx].awayGoals = ag
                    fixtures[idx].isPlayed = true
                    progressed = true
                }
                let before = (stage, fixtures.count)
                rollStage()
                if stage != before.0 || fixtures.count != before.1 { progressed = true }
            }
        }

        /// Records a match the user played, and moves the tournament on if
        /// that completes a stage.
        public mutating func recordResult(fixtureId: UUID, homeGoals: Int, awayGoals: Int, shootout: PenaltyShootout? = nil) {
            guard let idx = fixtures.firstIndex(where: { $0.id == fixtureId }) else { return }
            fixtures[idx].homeGoals = homeGoals
            fixtures[idx].awayGoals = awayGoals
            fixtures[idx].shootout = shootout
            fixtures[idx].isPlayed = true
            rollStage()
        }

        /// Moves from the group stage to the knockouts, and draws each
        /// knockout round once the one before it is finished.
        private mutating func rollStage() {
            if stage == .groupStage {
                guard groupStageComplete else { return }
                stage = .knockout
                generateNextKnockoutRound()
                return
            }
            guard stage == .knockout else { return }
            guard let round = activeKnockoutRound else {
                finishTournament()
                return
            }
            if fixtures.filter({ $0.stage == round }).isEmpty {
                generateNextKnockoutRound()
            }
        }

        /// Rest days before a round and games played per day, after the
        /// previous round ends.
        private static func knockoutPlan(_ round: String) -> (gap: Int, perDay: Int) {
            switch round {
            case "Round of 32": return (1, 3)
            case "Round of 16": return (1, 2)
            case "Quarter-Final": return (2, 2)
            case "Semi-Final": return (2, 1)
            case "Third Place": return (3, 1)
            default: return (1, 1)   // Final
            }
        }

        private func scheduled(_ games: [Fixture], round: String) -> [Fixture] {
            guard let previous = fixtures.compactMap({ $0.date }).max() else { return games }
            let plan = Self.knockoutPlan(round)
            var day = TournamentDates.add(previous, days: plan.gap)
            var out = games
            for i in out.indices {
                if i > 0 && i % plan.perDay == 0 { day = TournamentDates.add(day, days: 1) }
                out[i].date = day
            }
            return out
        }

        private mutating func finishTournament() {
            guard stage != .complete else { return }
            stage = .complete
            guard let final = fixtures.first(where: { $0.stage == "Final" && $0.isPlayed }) else { return }
            let ranked = participantIds
            let ranking: (String) -> Int = { id in ranked.firstIndex(of: id) ?? 999 }
            championId = tieWinner(final.homeTeamId, final.awayTeamId, stage: "Final", ranking: ranking)
        }

        /// Winner of a single-elimination tie (draws resolved by higher-ranked team).
        private func tieWinner(_ a: String, _ b: String, stage: String, ranking: (String) -> Int) -> String {
            guard let f = fixtures.first(where: {
                $0.stage == stage && $0.isPlayed &&
                (($0.homeTeamId == a && $0.awayTeamId == b) || ($0.homeTeamId == b && $0.awayTeamId == a))
            }) else { return a }
            if let shootout = f.shootout { return shootout.home > shootout.away ? f.homeTeamId : f.awayTeamId }
            if f.homeGoals > f.awayGoals { return f.homeTeamId }
            if f.awayGoals > f.homeGoals { return f.awayTeamId }
            return ranking(a) <= ranking(b) ? a : b
        }

        private mutating func generateNextKnockoutRound() {
            guard let round = activeKnockoutRound else {
                finishTournament()
                return
            }

            var newFixtures: [Fixture] = []
            // `participantIds` is seeded in FIFA-ranking order by the builder, so
            // it doubles as the tie-break ranking for drawn knockout matches.
            let ranked = participantIds
            let ranking: (String) -> Int = { id in ranked.firstIndex(of: id) ?? 999 }

            switch round {
            case "Round of 32":
                let qualifiers = Array(groupQualifiers().prefix(32))
                guard qualifiers.count >= 32 else { return }
                for i in 0..<16 {
                    newFixtures.append(Fixture(homeTeamId: qualifiers[i], awayTeamId: qualifiers[31 - i], stage: round))
                }

            case "Round of 16":
                if fixtures.contains(where: { $0.stage == "Round of 32" }) {
                    let field = knockoutWinners(from: "Round of 32", ranking: ranking)
                    guard field.count >= 16 else { return }
                    for i in 0..<8 {
                        newFixtures.append(Fixture(homeTeamId: field[i], awayTeamId: field[15 - i], stage: round))
                    }
                    break
                }
                let qualifiers = Array(groupQualifiers().prefix(16))
                guard qualifiers.count >= 16 else { return }
                let winners = Array(qualifiers.prefix(8))
                let runnersUp = Array(qualifiers.suffix(8))
                for i in 0..<8 {
                    let home = winners[i]
                    let away = runnersUp[(i + 1) % runnersUp.count]
                    newFixtures.append(Fixture(homeTeamId: home, awayTeamId: away, stage: round))
                }

            case "Quarter-Final":
                let contenders: [String]
                if fixtures.contains(where: { $0.stage == "Round of 16" }) {
                    contenders = knockoutWinners(from: "Round of 16", ranking: ranking)
                } else {
                    contenders = Array(groupQualifiers().prefix(8))
                }
                guard contenders.count >= 4 else { return }
                let field = Array(contenders.prefix(8))
                for i in 0..<(field.count / 2) {
                    newFixtures.append(
                        Fixture(homeTeamId: field[i], awayTeamId: field[field.count - 1 - i], stage: round)
                    )
                }

            case "Semi-Final":
                let contenders: [String]
                if fixtures.contains(where: { $0.stage == "Quarter-Final" }) {
                    contenders = knockoutWinners(from: "Quarter-Final", ranking: ranking)
                } else {
                    contenders = Array(groupQualifiers().prefix(4))
                }
                guard contenders.count >= 4 else { return }
                let field = Array(contenders.prefix(4))
                for i in 0..<(field.count / 2) {
                    newFixtures.append(
                        Fixture(homeTeamId: field[i], awayTeamId: field[field.count - 1 - i], stage: round)
                    )
                }

            case "Third Place":
                let losers = knockoutLosers(from: "Semi-Final", ranking: ranking)
                if losers.count >= 2 {
                    newFixtures.append(Fixture(homeTeamId: losers[0], awayTeamId: losers[1], stage: round))
                }

            case "Final":
                let winners = knockoutWinners(from: "Semi-Final", ranking: ranking)
                if winners.count >= 2 {
                    newFixtures.append(Fixture(homeTeamId: winners[0], awayTeamId: winners[1], stage: round))
                }

            default:
                break
            }

            fixtures.append(contentsOf: scheduled(newFixtures, round: round))
        }

        /// All qualifiers (winners then runners-up) across every group.
        private func groupQualifiers() -> [String] {
            var winners: [String] = []
            var runnersUp: [String] = []
            var thirdPlaced: [GroupRow] = []
            for group in groupNames {
                let table = table(forGroup: group)
                if table.count >= 1 { winners.append(table[0].teamId) }
                if table.count >= 2 { runnersUp.append(table[1].teamId) }
                if table.count >= 3 { thirdPlaced.append(table[2]) }
            }
            // If 6 groups (24 teams like EURO/AFCON/Asian Cup), take top 4 third-placed teams
            // to make a full 16-nation knockout bracket.
            if winners.count == 12 && runnersUp.count == 12 {
                // 48 teams: the eight best third-placed sides join the last 32.
                let bestThird = thirdPlaced.sorted(by: GroupRow.sort).prefix(8).map { $0.teamId }
                return winners + runnersUp + bestThird
            }
            if winners.count == 6 && runnersUp.count == 6 {
                let sortedThird = thirdPlaced.sorted(by: GroupRow.sort)
                let bestThird = sortedThird.prefix(4).map { $0.teamId }
                return winners + runnersUp + bestThird
            }
            return winners + runnersUp
        }

        private func knockoutWinners(from stage: String, ranking: (String) -> Int) -> [String] {
            let roundFixtures = fixtures.filter { $0.stage == stage && $0.isPlayed }
            var seen = Set<String>()
            var winners: [String] = []
            for f in roundFixtures {
                if seen.contains(f.homeTeamId) { continue }
                let a = f.homeTeamId, b = f.awayTeamId
                seen.insert(a); seen.insert(b)
                winners.append(tieWinner(a, b, stage: stage, ranking: ranking))
            }
            return winners
        }

        private func knockoutLosers(from stage: String, ranking: (String) -> Int) -> [String] {
            let roundFixtures = fixtures.filter { $0.stage == stage && $0.isPlayed }
            var losers: [String] = []
            for f in roundFixtures {
                let winner = tieWinner(f.homeTeamId, f.awayTeamId, stage: stage, ranking: ranking)
                losers.append(winner == f.homeTeamId ? f.awayTeamId : f.homeTeamId)
            }
            return losers
        }
    }
}

/// Day arithmetic on "yyyy-MM-dd" strings, the game's date format.
enum TournamentDates {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func add(_ date: String, days: Int) -> String {
        guard let d = formatter.date(from: date) else { return date }
        return formatter.string(from: d.addingTimeInterval(Double(days) * 86_400))
    }
}
