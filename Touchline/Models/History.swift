//
//  History.swift
//  Touchline
//
//  The record books: every league, cup and European champion, the world's
//  individual awards, and each managed club's greatest players. Honours are
//  recorded at the end of every season and kept for the whole career.
//

import Foundation

/// A trophy (or promotion) won in a season.
public struct HonourRecord: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable {
        case league, cup, europe
    }

    public var id: UUID
    public var season: String
    public var competition: String
    public var kind: Kind
    public var clubId: UUID
    public var clubName: String
    public var runnerUpName: String?

    public init(season: String, competition: String, kind: Kind, clubId: UUID, clubName: String, runnerUpName: String? = nil) {
        self.id = UUID()
        self.season = season
        self.competition = competition
        self.kind = kind
        self.clubId = clubId
        self.clubName = clubName
        self.runnerUpName = runnerUpName
    }
}

/// An individual award at the end of a season.
public struct AwardRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var season: String
    public var award: String
    public var playerId: UUID
    public var playerName: String
    public var clubName: String
    public var detail: String

    public init(season: String, award: String, playerId: UUID, playerName: String, clubName: String, detail: String) {
        self.id = UUID()
        self.season = season
        self.award = award
        self.playerId = playerId
        self.playerName = playerName
        self.clubName = clubName
        self.detail = detail
    }
}

/// A player's whole career at one club, for the Hall of Fame.
public struct LegendRecord: Codable, Hashable, Identifiable {
    public var id: UUID            // the player's id
    public var name: String
    public var position: String
    public var appearances: Int
    public var goals: Int
    public var assists: Int
    public var seasons: Int
    public var firstSeason: String
    public var lastSeason: String
    public var bestRating: Int
}

/// Everything the record books keep across a career.
public struct WorldHistory: Codable, Hashable {
    public var honours: [HonourRecord]
    public var awards: [AwardRecord]
    /// Hall of Fame entries for the clubs the user has run, keyed by club id.
    public var legends: [String: [LegendRecord]]

    public init(honours: [HonourRecord] = [], awards: [AwardRecord] = [], legends: [String: [LegendRecord]] = [:]) {
        self.honours = honours
        self.awards = awards
        self.legends = legends
    }

    private enum CodingKeys: String, CodingKey { case honours, awards, legends }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        honours = try c.decodeIfPresent([HonourRecord].self, forKey: .honours) ?? []
        awards = try c.decodeIfPresent([AwardRecord].self, forKey: .awards) ?? []
        legends = try c.decodeIfPresent([String: [LegendRecord]].self, forKey: .legends) ?? [:]
    }

    /// Trophies won by one club, newest first.
    public func honours(for clubId: UUID) -> [HonourRecord] {
        honours.filter { $0.clubId == clubId }.reversed()
    }

    /// Past winners of a competition, newest first.
    public func champions(of competition: String) -> [HonourRecord] {
        honours.filter { $0.competition == competition }.reversed()
    }

    /// The Hall of Fame for a club, by appearances.
    public func legends(for clubId: UUID) -> [LegendRecord] {
        (legends[clubId.uuidString] ?? []).sorted {
            ($0.appearances, $0.goals) > ($1.appearances, $1.goals)
        }
    }
}

extension GameState {

    /// Combines archived trophies with wins confirmed in the ongoing season.
    func trophyCabinet(for club: Club) -> [HonourRecord] {
        let archived = history.honours(for: club.id)
        let year = season.year
        var current: [HonourRecord] = []

        func add(_ competition: String, kind: HonourRecord.Kind) {
            guard !archived.contains(where: { $0.season == year && $0.competition == competition && $0.kind == kind }) else { return }
            current.append(HonourRecord(season: year, competition: competition, kind: kind, clubId: club.id, clubName: club.name))
        }

        for league in leagues where league.clubIds.contains(club.id) {
            if clinchedHonours.contains(clinchedHonourKey(.champions, clubId: club.id, league: league)) {
                add(league.name, kind: .league)
            }
        }
        for cup in domesticCups where cup.championClubId == club.id {
            add(cup.name, kind: .cup)
        }
        for competition in europeanCompetitions where competition.championClubId == club.id {
            add(competition.competition.displayName, kind: .europe)
        }
        return current + archived
    }

    // MARK: - Recording a season

    /// Records champions, awards and the user's club legends. Called once at
    /// the end of each season, before promotion and relegation.
    func recordSeasonHistory(finalTables: [LeagueTier: [LeagueStanding]]) {
        let year = season.year
        // League champions.
        for league in leagues {
            guard let table = finalTables[league.tier], let first = table.first,
                  let winner = club(withId: first.clubId) else { continue }
            let runnerUp = table.count > 1 ? club(withId: table[1].clubId)?.name : nil
            history.honours.append(HonourRecord(season: year, competition: league.name, kind: .league,
                                                clubId: winner.id, clubName: winner.name, runnerUpName: runnerUp))
        }
        // Domestic cups.
        for cup in domesticCups {
            guard let championId = cup.championClubId, let winner = club(withId: championId) else { continue }
            history.honours.append(HonourRecord(season: year, competition: cup.name, kind: .cup,
                                                clubId: winner.id, clubName: winner.name))
        }
        // European competitions.
        for competition in europeanCompetitions {
            guard let championId = competition.championClubId, let winner = club(withId: championId) else { continue }
            let final = competition.fixtures.first { $0.stage == "Final" && $0.isPlayed }
            let runnerUp = final.flatMap { f in [f.homeClubId, f.awayClubId].first { $0 != championId } }
                .flatMap { club(withId: $0)?.name }
            history.honours.append(HonourRecord(season: year, competition: competition.competition.displayName,
                                                kind: .europe, clubId: winner.id, clubName: winner.name,
                                                runnerUpName: runnerUp))
        }
        recordWorldAwards(finalTables: finalTables)
        recordLegends()
        recordPlayerCareers()
    }

    /// Adds this season to the career log of notable players: everyone at the
    /// user's club, top-flight regulars and promising youngsters. Keeps the
    /// last twelve seasons per player.
    private func recordPlayerCareers() {
        for c in clubs.indices {
            let club = clubs[c]
            let isUsers = club.isUserClub
            for p in club.players.indices {
                let player = club.players[p]
                let stats = player.seasonStats
                let notable = isUsers
                    || (club.leagueTier.level == 1 && stats.appearances >= 10)
                    || (player.age <= 21 && player.potential >= 80)
                    || player.careerLog != nil
                guard notable, stats.appearances > 0 || isUsers else { continue }
                var log = player.careerLog ?? []
                log.append(PlayerSeasonLine(season: season.year, club: club.shortName,
                                            appearances: stats.appearances, goals: stats.goals,
                                            assists: stats.assists, averageRating: stats.averageRating,
                                            overall: player.overall,
                                            cleanSheets: stats.cleanSheets, goalsConceded: stats.goalsConceded))
                if log.count > 12 { log.removeFirst(log.count - 12) }
                clubs[c].players[p].careerLog = log
            }
        }
    }

    /// World-wide individual awards among the top flights of Europe's big
    /// five leagues.
    private func recordWorldAwards(finalTables: [LeagueTier: [LeagueStanding]]) {
        let year = season.year
        // Every league in the world, top flight and below. The awards weigh
        // the strength of the league (see seasonScore), so a big season in a
        // small league does not outrank one in the Premier League.
        let champions = Set(finalTables.values.compactMap { $0.first?.clubId })
        let pool = clubs.flatMap { club in club.players.map { (player: $0, club: club) } }
            .filter { $0.player.seasonStats.appearances >= 20 }
        guard !pool.isEmpty else { return }

        func give(_ award: String, _ entry: (player: Player, club: Club)?, _ detail: (Player) -> String) {
            guard let entry else { return }
            let record = AwardRecord(season: year, award: award, playerId: entry.player.id,
                                     playerName: entry.player.fullName, clubName: entry.club.name,
                                     detail: detail(entry.player))
            history.awards.append(record)
            addNews(
                headline: "\(award): \(entry.player.fullName)",
                body: "\(entry.player.fullName) of \(entry.club.name) wins the \(award) for \(year). \(record.detail).",
                category: .award,
                sender: entry.club.id == userClubId ? "Awards Committee" : "World Football Awards"
            )
        }
        // The Golden Shoe: goals weighted by the league, as the real award
        // is (double in Europe's big five, one and a half in other top
        // flights). It goes to the top scorer as the season ends.
        let bigFive: Set<LeagueCountry> = [.england, .spain, .italy, .germany, .france]
        func shoePoints(_ entry: (player: Player, club: Club)) -> Double {
            let tier = entry.club.leagueTier
            let factor = tier.level == 1 ? (bigFive.contains(tier.country) ? 2.0 : 1.5) : 1.0
            return Double(entry.player.seasonStats.goals) * factor
        }
        give("European Golden Shoe", pool.max { shoePoints($0) < shoePoints($1) }) {
            "\($0.seasonStats.goals) goals in \($0.seasonStats.appearances) games"
        }
        // The Ballon d'Or and the Team of the Year are decided now but
        // presented later, in October and January. Lifting the Champions
        // League counts for a lot.
        var winners = champions
        if let europeanChampion = europeanCompetitions.first(where: { $0.competition == .championsLeague })?.championClubId {
            winners.insert(europeanChampion)
        }
        scheduleAwardCeremonies(pool: pool, champions: winners)
    }
    /// Adds this season's appearances to the Hall of Fame of the user's club.
    private func recordLegends() {
        guard let club = userClub else { return }
        let key = club.id.uuidString
        var book = history.legends[key] ?? []
        for player in club.players where player.seasonStats.appearances > 0 && !player.isOnLoan {
            let s = player.seasonStats
            if let idx = book.firstIndex(where: { $0.id == player.id }) {
                book[idx].appearances += s.appearances
                book[idx].goals += s.goals
                book[idx].assists += s.assists
                book[idx].seasons += 1
                book[idx].lastSeason = season.year
                book[idx].bestRating = max(book[idx].bestRating, player.overall)
                book[idx].name = player.fullName
            } else {
                book.append(LegendRecord(id: player.id, name: player.fullName,
                                         position: player.primaryPosition.abbreviation,
                                         appearances: s.appearances, goals: s.goals, assists: s.assists,
                                         seasons: 1, firstSeason: season.year, lastSeason: season.year,
                                         bestRating: player.overall))
            }
        }
        // Keep the book a sensible size: the top hundred by appearances.
        book.sort { ($0.appearances, $0.goals) > ($1.appearances, $1.goals) }
        history.legends[key] = Array(book.prefix(100))
    }

    // MARK: - Shortlist

    public func isShortlisted(_ playerId: UUID) -> Bool { shortlist.contains(playerId) }

    public func toggleShortlist(_ playerId: UUID) {
        if let idx = shortlist.firstIndex(of: playerId) {
            shortlist.remove(at: idx)
        } else {
            shortlist.append(playerId)
        }
    }

    /// Shortlisted players who still exist, with their current club.
    public var shortlistedPlayers: [(player: Player, club: Club?)] {
        shortlist.compactMap { player(withId: $0) }
    }
}

// MARK: - Pre-match odds

/// Win/draw/loss probabilities for a fixture.
public struct MatchOdds: Hashable {
    public var home: Double
    public var draw: Double
    public var away: Double

    /// Bookmaker-style decimal price with a small margin, e.g. 2.10.
    public static func decimal(_ probability: Double) -> Double {
        guard probability > 0 else { return 99 }
        return max(1.01, (1 / probability) * 0.94)
    }
}

extension GameState {
    /// Probabilities from the two starting elevens, fitted to this game's
    /// match engine over a full simulated season: draws are about a quarter
    /// of even games and rarer in mismatches, and home advantage is worth
    /// roughly two and a half rating points.
    public func matchOdds(for fixture: Fixture) -> MatchOdds? {
        guard let home = club(withId: fixture.homeClubId),
              let away = club(withId: fixture.awayClubId) else { return nil }
        let gap = home.startingXIAverageOverall - away.startingXIAverageOverall
        let draw = max(0.15, 0.26 - 0.011 * abs(gap))
        let logit = max(-2.6, min(2.6, 0.62 + 0.22 * gap))
        let homeShare = 1 / (1 + exp(-logit))
        return MatchOdds(home: (1 - draw) * homeShare, draw: draw, away: (1 - draw) * (1 - homeShare))
    }
}
