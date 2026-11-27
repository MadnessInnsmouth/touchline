//
//  Clinching.swift
//  Touchline
//
//  Titles and promotion are decided the moment nobody can catch you, not on
//  the last day: twenty points clear with four games left, you are
//  champions now. When it is your club (or you lift a cup or a European
//  trophy) the moment gets its own celebration screen.
//

import Foundation

/// A moment of glory for the user's club, shown full screen.
public struct Celebration: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable {
        case champions, promotion, cup, europe
    }

    public var id: UUID
    public var kind: Kind
    public var clubId: UUID
    /// "CHAMPIONS!"
    public var title: String
    /// "Premier League 2026-27 · with 4 games to spare"
    public var subtitle: String
}

extension GameState {

    /// Checks every division for a title or automatic promotion that can no
    /// longer be taken away, and crowns it at once. Runs after each round
    /// of fixtures (and on the last day, so a final-day title is celebrated
    /// too).
    func checkClinches() {
        let higherTiers = Set(leagues.map(\.tier))
        for league in leagues {
            let fixtures = season.fixtures.filter { $0.competition == league.name && $0.cupRound == nil }
            guard !fixtures.isEmpty, fixtures.contains(where: \.isPlayed) else { continue }
            var remaining: [UUID: Int] = [:]
            for f in fixtures where !f.isPlayed {
                remaining[f.homeClubId, default: 0] += 1
                remaining[f.awayClubId, default: 0] += 1
            }
            let table = standings(for: league)
            guard table.count >= 2 else { continue }
            func ceiling(_ row: LeagueStanding) -> Int { row.points + 3 * (remaining[row.clubId] ?? 0) }

            // Before the final whistle, use the points ceiling. Once all games
            // are played, the sorted table has already applied the tie-breakers.
            let leader = table[0]
            if remaining.isEmpty || table.dropFirst().allSatisfy({ ceiling($0) < leader.points }) {
                clinch(.champions, clubId: leader.clubId, league: league, gamesLeft: remaining[leader.clubId] ?? 0)
            }

            // Automatic promotion: no one outside the places can catch you.
            let tier = league.tier
            if !tier.isTopFlight, let up = tier.higherTier, higherTiers.contains(up) {
                let places = min(tier.autoPromotionCount, table.count - 1)
                if places > 0 {
                    let bestChaser = table.dropFirst(places).map(ceiling).max() ?? 0
                    for row in table.prefix(places) where row.points > bestChaser {
                        clinch(.promotion, clubId: row.clubId, league: league, gamesLeft: remaining[row.clubId] ?? 0,
                               toLeague: leagues.first { $0.tier == up }?.name ?? up.displayName)
                    }
                }
            }
        }
    }

    func clinchedHonourKey(_ kind: Celebration.Kind, clubId: UUID, league: League) -> String {
        "\(kind.rawValue)|\(league.name)|\(season.year)|\(clubId.uuidString)"
    }

    private func clinch(_ kind: Celebration.Kind, clubId: UUID, league: League, gamesLeft: Int, toLeague: String? = nil) {
        let key = clinchedHonourKey(kind, clubId: clubId, league: league)
        guard !clinchedHonours.contains(key) else { return }
        clinchedHonours.append(key)
        let name = clubName(for: clubId)
        let spare = gamesLeft == 0 ? "on the final day"
            : "with \(gamesLeft) game\(gamesLeft == 1 ? "" : "s") to spare"
        let isUsers = clubId == userClubId
        switch kind {
        case .champions:
            addNews(
                headline: isUsers ? "CHAMPIONS!" : "\(name) Crowned Champions",
                body: "\(name) are \(league.name) champions for \(season.year), \(spare). Nobody can catch them now.",
                category: .award,
                sender: isUsers ? "The Board" : NewsItem.newsDesk
            )
            if isUsers {
                celebrate(.champions, clubId: clubId, title: "CHAMPIONS!",
                          subtitle: "\(league.name) \(season.year) · \(spare)")
            }
        case .promotion:
            let target = toLeague ?? "the division above"
            addNews(
                headline: isUsers ? "PROMOTED!" : "\(name) Clinch Promotion",
                body: "\(name) are going up to the \(target), \(spare).",
                category: .promotion,
                sender: isUsers ? "The Board" : NewsItem.newsDesk
            )
            if isUsers {
                if var pending = celebrationToShow, pending.kind == .champions, pending.clubId == clubId {
                    // Champions and promoted on the same day: one screen.
                    pending.subtitle += " · Promoted to the \(target)"
                    celebrationToShow = pending
                } else {
                    celebrate(.promotion, clubId: clubId, title: "PROMOTED!",
                              subtitle: "Up to the \(target) · \(spare)")
                }
            }
        case .cup, .europe:
            break
        }
    }

    /// Queues a celebration screen for the user's club.
    func celebrate(_ kind: Celebration.Kind, clubId: UUID, title: String, subtitle: String) {
        celebrationToShow = Celebration(id: UUID(), kind: kind, clubId: clubId, title: title, subtitle: subtitle)
    }
}
