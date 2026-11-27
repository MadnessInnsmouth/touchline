//
//  NationalManagement.swift
//  Touchline
//
//  Managing a national team for real: the manager picks the eleven, the
//  formation and the approach, and plays the nation's tournament matches
//  with the full match engine (extra time and penalties in the knockouts).
//  Everyone else's international matches are still simulated.
//

import Foundation

/// A finished international match the user managed, for its report.
public struct InternationalReport: Codable, Hashable, Identifiable {
    public var id: UUID
    public var tournament: String
    public var stage: String
    public var date: String
    public var homeName: String
    public var awayName: String
    public var homeGoals: Int
    public var awayGoals: Int
    public var shootout: PenaltyShootout? = nil
    /// Whether the user's nation was the home side.
    public var userIsHome: Bool
    public var events: [MatchEvent]

    public var scoreLine: String { "\(homeName) \(homeGoals)-\(awayGoals) \(awayName)" + (shootout.map { " (\($0.scoreText))" } ?? "") }
    public var userWon: Bool {
        if let shootout { return userIsHome ? shootout.home > shootout.away : shootout.away > shootout.home }
        return userIsHome ? homeGoals > awayGoals : awayGoals > homeGoals
    }
    public var isDraw: Bool { homeGoals == awayGoals && shootout == nil }
}

extension GameState {

    /// The managed nation's next match that is due (dated today or earlier)
    /// and waiting to be played.
    public var dueInternationalMatch: (tournament: InternationalTournament.State, fixture: InternationalTournament.Fixture)? {
        guard Self.internationalFootballEnabled, gameMode == .manageClub, let teamId = managedNationalTeamId else { return nil }
        let today = season.currentDate
        var best: (InternationalTournament.State, InternationalTournament.Fixture)?
        for tournament in internationalTournaments where tournament.stage != .complete {
            for fixture in tournament.fixtures where !fixture.isPlayed
                && (fixture.homeTeamId == teamId || fixture.awayTeamId == teamId)
                && (fixture.date ?? "") <= today {
                if best == nil || (fixture.date ?? "") < (best!.1.date ?? "") { best = (tournament, fixture) }
            }
        }
        return best.map { (tournament: $0.0, fixture: $0.1) }
    }

    /// The managed nation's next scheduled match, due or not.
    public var nextInternationalFixture: (tournament: InternationalTournament.State, fixture: InternationalTournament.Fixture)? {
        guard let teamId = managedNationalTeamId else { return nil }
        var best: (InternationalTournament.State, InternationalTournament.Fixture)?
        for tournament in internationalTournaments where tournament.stage != .complete {
            for fixture in tournament.fixtures where !fixture.isPlayed
                && (fixture.homeTeamId == teamId || fixture.awayTeamId == teamId) {
                if best == nil || (fixture.date ?? "") < (best!.1.date ?? "") { best = (tournament, fixture) }
            }
        }
        return best.map { (tournament: $0.0, fixture: $0.1) }
    }

    /// A national team as a side the match engine can play: its squad, and
    /// the user's eleven and tactics if it is the user's nation.
    func matchSide(for team: NationalTeam, tactics: Tactics?) -> Club {
        var side = Club(
            name: team.name,
            shortName: String(team.name.prefix(3)).uppercased(),
            stadium: "the national stadium",
            stadiumCapacity: 60_000,
            city: team.name,
            primaryColor: "#1F3A93",
            secondaryColor: "#FFFFFF",
            leagueTier: .eng1,
            reputation: Int(team.strength),
            players: team.players,
            tactics: tactics
        )
        let squadIds = Set(team.players.map(\.id))
        if let tactics, tactics.startingXI.count == 11, tactics.startingXI.allSatisfy({ squadIds.contains($0) }) {
            side.tactics = tactics
            if side.tactics.substitutes.isEmpty {
                side.tactics.substitutes = team.players
                    .filter { !tactics.startingXI.contains($0.id) }
                    .sorted { $0.overall > $1.overall }
                    .prefix(9).map(\.id)
            }
        } else {
            side.autoPickStartingXI()
        }
        side.ensureTacticalIntegrity()
        return side
    }

    /// The user's chosen eleven for his nation, or the best eleven if none
    /// has been picked.
    public var nationalSelection: Tactics {
        if let team = managedNationalTeam {
            let squadIds = Set(team.players.map(\.id))
            if let chosen = nationalTactics, chosen.startingXI.count == 11,
               chosen.startingXI.allSatisfy({ squadIds.contains($0) }) {
                return chosen
            }
            var side = matchSide(for: team, tactics: nil)
            side.tactics.formation = nationalTactics?.formation ?? side.tactics.formation
            side.tactics.mentality = nationalTactics?.mentality ?? side.tactics.mentality
            return side.tactics
        }
        return Tactics.defaultTactics
    }

    /// Plays the managed nation's due match with the user's selection.
    /// Returns the report, or nil if no match is due.
    @discardableResult
    public func playInternationalMatch() -> InternationalReport? {
        guard let due = dueInternationalMatch,
              let teamId = managedNationalTeamId,
              let tIdx = internationalTournaments.firstIndex(where: { $0.id == due.tournament.id }),
              let home = nationalTeam(withId: due.fixture.homeTeamId),
              let away = nationalTeam(withId: due.fixture.awayTeamId) else { return nil }
        let userIsHome = home.id == teamId
        var homeSide = matchSide(for: home, tactics: userIsHome ? nationalSelection : nil)
        var awaySide = matchSide(for: away, tactics: userIsHome ? nil : nationalSelection)
        let config = MatchEngine.SimulationConfig(
            neutralVenue: true,
            matchWeek: 1,
            competition: due.tournament.title,
            date: due.fixture.date ?? season.currentDate,
            // Group games can be drawn; knockout ties go to extra time and penalties.
            isKnockout: !due.fixture.stage.hasPrefix("Group")
        )
        let result = MatchEngine.simulateFullMatch(home: &homeSide, away: &awaySide, config: config)

        var tournament = internationalTournaments[tIdx]
        tournament.recordResult(fixtureId: due.fixture.id, homeGoals: result.homeGoals, awayGoals: result.awayGoals, shootout: result.shootout)
        internationalTournaments[tIdx] = tournament

        let report = InternationalReport(
            id: UUID(),
            tournament: due.tournament.title,
            stage: due.fixture.stage,
            date: due.fixture.date ?? season.currentDate,
            homeName: home.name,
            awayName: away.name,
            homeGoals: result.homeGoals,
            awayGoals: result.awayGoals,
            shootout: result.shootout,
            userIsHome: userIsHome,
            events: result.events
        )
        lastInternationalReport = report
        let nation = userIsHome ? home.name : away.name
        let opponent = userIsHome ? away.name : home.name
        addNews(
            headline: "\(report.tournament): \(report.scoreLine)",
            body: report.isDraw
                ? "\(nation) and \(opponent) draw in the \(report.stage.lowercased())."
                : (report.userWon
                    ? "Victory for \(nation) over \(opponent) in the \(report.stage.lowercased())."
                    : "Defeat for \(nation) against \(opponent) in the \(report.stage.lowercased())."),
            category: .result,
            sender: "\(nation) Federation"
        )
        // The rest of the day's matches, and the next round if this one is done.
        advanceInternationalTournaments()
        return report
    }
}
