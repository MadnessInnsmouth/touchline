//
//  PostMatchView.swift
//  Touchline
//
//  Full time in three screens. The report: the scoreboard with each side's
//  scorers, Match Facts (goals, cards, injuries and changes in order), player
//  ratings and team stats. Then Player of the Match. Then the other results
//  and the table.
//

import SwiftUI

public struct PostMatchView: View {
    @Environment(GameState.self) private var gameState
    @State private var showElsewhere = true

    /// Full time in three screens: the report, Player of the Match, then the
    /// rest of the round.
    private enum Step: Hashable { case report, playerOfMatch, results }
    @State private var step: Step = .report
    @State private var playedVerdict = false
    /// The player-of-the-match profile opens over this screen, so closing it
    /// comes straight back here.
    @State private var profilePlayerId: UUID?
    @AccessibilityFocusState(for: .voiceOver) private var focusedStep: Step?

    public var body: some View {
        ScrollView {
            if let fixture = gameState.activeMatchFixture,
               let res = fixture.result,
               let home = gameState.club(withId: fixture.homeClubId),
               let away = gameState.club(withId: fixture.awayClubId) {
                VStack(spacing: 16) {
                    switch step {
                    case .report:
                        scoreboard(fixture: fixture, res: res, home: home, away: away)
                            // Read as one line, first: "Full time. Arsenal 2, Chelsea 1. Victory."
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(fullTimeSummary(res: res, home: home, away: away))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($focusedStep, equals: .report)
                        matchFactsCard(res: res, home: home, away: away)
                        ratingsCard(res: res)
                        statsCard(res: res, home: home, away: away)
                    case .playerOfMatch:
                        if let potm = potmPlayer(for: res) {
                            playerOfMatchScreen(potm, res: res)
                        } else {
                            Text("No player of the match was recorded.")
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($focusedStep, equals: .playerOfMatch)
                                .foregroundStyle(.secondary)
                                .padding(.top, 60)
                        }
                    case .results:
                        Text(fixture.cupRound.map { "\(fixture.competition), \($0)" } ?? "\(fixture.competition), Matchweek \(gameState.leagueRound(of: fixture))")
                            .font(.gfDisplay(20))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($focusedStep, equals: .results)
                        elsewhereCard(fixture: fixture)
                        tableCard(fixture: fixture)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("No Match Summary", systemImage: "sportscourt",
                                       description: Text("Play a match to see the full-time recap."))
            }
        }
        .id(step)
        .safeAreaInset(edge: .bottom) {
            Group {
                if step == .results {
                    actions
                } else {
                    Button {
                        step = step == .report ? .playerOfMatch : .results
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(.gfPrimary)
                    .accessibilityHint(step == .report ? "Shows the player of the match" : "Shows the other results")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .stadiumBackground()
        .navigationTitle(step == .report ? "Full Time" : step == .playerOfMatch ? "Player of the Match" : "Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task(id: step) { [step] in
            // Wait for the new heading to enter the accessibility tree.
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                focusedStep = step
            } catch {
                // The report closed or another page took its place.
            }
        }
        .sheet(isPresented: Binding(get: { profilePlayerId != nil }, set: { if !$0 { profilePlayerId = nil } })) {
            if let id = profilePlayerId {
                NavigationStack { PlayerDetailView(playerId: id) }
            }
        }
        .onAppear {
            guard !playedVerdict,
                  let fixture = gameState.activeMatchFixture,
                  let res = fixture.result,
                  let userClub = gameState.userClub else { return }
            playedVerdict = true
            let outcome = res.outcomeLetter(for: userClub.id)
            // The crowd's verdict, for live and simulated matches alike; the
            // short tones are kept for when crowd sound is turned off.
            if UserDefaults.standard.bool(forKey: CrowdAtmosphere.enabledKey) {
                CrowdAtmosphere.shared.resultVerdict(outcome: outcome)
            } else {
                switch outcome {
                case "W": SoundManager.shared.play(.win, enabled: gameState.soundEnabled)
                case "L": SoundManager.shared.play(.loss, enabled: gameState.soundEnabled)
                default: SoundManager.shared.play(.draw, enabled: gameState.soundEnabled)
                }
            }
        }
    }

    // MARK: - Scoreboard

    /// "Full time. Arsenal 2, Chelsea 1. Victory. Goals: Saka 23', Havertz 61'; Palmer 80'."
    private func fullTimeSummary(res: MatchResult, home: Club, away: Club) -> String {
        let outcome = gameState.userClubId.map { res.outcomeLetter(for: $0) } ?? "-"
        let verdict = outcome == "W" ? " Victory." : outcome == "D" ? " Draw." : outcome == "L" ? " Defeat." : ""
        func scorers(_ home: Bool) -> String {
            res.goalEvents.filter { $0.isHomeTeam == home }
                .map { "\($0.playerId.flatMap { gameState.player(withId: $0)?.player.lastName } ?? "Goal") \($0.minute)'" }
                .joined(separator: ", ")
        }
        let goals = res.homeGoals + res.awayGoals > 0
            ? " Goals: \([scorers(true), scorers(false)].filter { !$0.isEmpty }.joined(separator: "; "))."
            : ""
        let penalties = res.shootout.map { " Penalties: \(home.name) \($0.home), \(away.name) \($0.away)." } ?? ""
        return "Full time. \(home.name) \(res.homeGoals), \(away.name) \(res.awayGoals).\(penalties)\(verdict)\(goals)"
    }

    /// Crests and names either side of a big score, with each side's scorers
    /// listed under its name.
    private func scoreboard(fixture: Fixture, res: MatchResult, home: Club, away: Club) -> some View {
        let outcome = gameState.userClubId.map { res.outcomeLetter(for: $0) } ?? "-"
        let homeScorers = res.goalEvents.filter { $0.isHomeTeam }
        let awayScorers = res.goalEvents.filter { !$0.isHomeTeam }
        return VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(fixture.cupRound.map { "\(fixture.competition) • \($0)" } ?? "\(fixture.competition) • Matchweek \(gameState.leagueRound(of: fixture))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if let derby = gameState.derbyName(for: fixture) {
                    GFPill(text: derby, color: .white, icon: "flame.fill")
                }
            }
            HStack(alignment: .top, spacing: 8) {
                teamColumn(home, scorers: homeScorers)
                VStack(spacing: 4) {
                    Text("\(res.homeGoals) - \(res.awayGoals)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .fixedSize()
                    Text("Full time")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                    if let shootout = res.shootout {
                        Text(shootout.scoreText).font(.caption.weight(.semibold))
                    }
                    if outcome != "-" {
                        Text(outcome == "W" ? "Victory" : outcome == "D" ? "Draw" : "Defeat")
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                (outcome == "W" ? Color.winGreen : outcome == "D" ? Color.drawGray : Color.lossRed),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .foregroundStyle(.white)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 8)
                teamColumn(away, scorers: awayScorers)
            }
            if res.attendance > 0 {
                Label("\(res.attendance.formatted()) at \(home.stadium)", systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: home.primaryColor), Color(hex: away.primaryColor)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardSummary(fixture: fixture, res: res, home: home, away: away, outcome: outcome))
        .accessibilityAddTraits(.isHeader)
    }

    private func scoreboardSummary(fixture: Fixture, res: MatchResult, home: Club, away: Club, outcome: String) -> String {
        func scorers(_ events: [MatchEvent]) -> String {
            events.map { "\(playerName($0.playerId) ?? "unknown") \($0.minute) minutes\($0.type == .penalty ? ", penalty" : $0.type == .ownGoal ? ", own goal" : "")" }
                .joined(separator: ", ")
        }
        var text = "Full time. \(home.name) \(res.homeGoals), \(away.name) \(res.awayGoals)."
        if outcome == "W" { text += " Victory." } else if outcome == "L" { text += " Defeat." } else if outcome == "D" { text += " Draw." }
        let h = res.goalEvents.filter { $0.isHomeTeam }, a = res.goalEvents.filter { !$0.isHomeTeam }
        if !h.isEmpty { text += " \(home.name) scorers: \(scorers(h))." }
        if !a.isEmpty { text += " \(away.name) scorers: \(scorers(a))." }
        text += " \(fixture.competition)."
        return text
    }

    private func teamColumn(_ club: Club, scorers: [MatchEvent]) -> some View {
        VStack(spacing: 6) {
            CrestView(club: club, size: 50)
            Text(club.name)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            VStack(spacing: 2) {
                ForEach(scorers) { goal in
                    HStack(spacing: 4) {
                        Image(systemName: "soccerball").accessibilityHidden(true).font(.system(size: 9))
                        Text("\(playerSurname(goal.playerId)) \(goal.minute)'\(goal.type == .penalty ? " (pen)" : goal.type == .ownGoal ? " (og)" : "")")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playerSurname(_ id: UUID?) -> String {
        guard let id, let player = gameState.player(withId: id)?.player else { return "Goal" }
        return player.lastName.isEmpty ? player.fullName : player.lastName
    }

    private func playerName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return gameState.player(withId: id)?.player.fullName
    }

    // MARK: - Match facts

    /// Goals, cards, injuries and substitutions together, in the order they
    /// happened. Goals keep their scorer, assist and description.
    @ViewBuilder
    private func matchFactsCard(res: MatchResult, home: Club, away: Club) -> some View {
        let kinds: Set<MatchEventType> = [.goal, .penalty, .ownGoal, .yellowCard, .redCard, .secondYellow, .injury, .substitution]
        let goalIds = Set(res.goalEvents.map(\.id))
        let rows: [(event: MatchEvent, score: String?)] = {
            var homeGoals = 0, awayGoals = 0
            return res.events.filter { kinds.contains($0.type) }.map { event in
                guard goalIds.contains(event.id) else { return (event, nil) }
                if event.isHomeTeam { homeGoals += 1 } else { awayGoals += 1 }
                return (event, "\(homeGoals)-\(awayGoals)")
            }
        }()
        VStack(alignment: .leading, spacing: 12) {
            GFSectionHeader(title: "Match Facts", icon: "list.bullet.rectangle")
            if rows.isEmpty {
                Text("No goals, cards or changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.event.id) { index, row in
                let event = row.event
                let club = event.isHomeTeam ? home : away
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Text("\(event.minute)'")
                            .font(.subheadline.weight(.heavy).monospacedDigit())
                        if let score = row.score {
                            Text(score)
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 42)
                    factIcon(event.type)
                        .frame(width: 18)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(factTitle(event))
                            .font(.subheadline.weight(row.score != nil ? .bold : .semibold))
                        if row.score != nil, let assist = playerName(event.assistPlayerId) {
                            Label("Assist: \(assist)", systemImage: "arrowshape.turn.up.right.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(club.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !event.detailText.isEmpty {
                            Text(event.detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(event.minute) minutes. \(factKind(event.type)). \(factTitle(event)), \(club.name).\(row.score.map { " Score \($0.replacingOccurrences(of: "-", with: " to "))." } ?? "") \(event.detailText)")
                if index < rows.count - 1 { Divider() }
            }
        }
        .gfCard()
    }

    private func factTitle(_ event: MatchEvent) -> String {
        if event.type == .substitution { return event.shortText }
        return playerName(event.playerId) ?? event.shortText
    }

    private func factKind(_ type: MatchEventType) -> String {
        switch type {
        case .goal: return "Goal"
        case .penalty: return "Penalty goal"
        case .ownGoal: return "Own goal"
        case .yellowCard: return "Yellow card"
        case .redCard: return "Red card"
        case .secondYellow: return "Second yellow card, sent off"
        case .injury: return "Injury"
        case .substitution: return "Substitution"
        default: return "Event"
        }
    }

    @ViewBuilder
    private func factIcon(_ type: MatchEventType) -> some View {
        switch type {
        case .goal, .penalty:
            Image(systemName: "soccerball").accessibilityHidden(true).font(.subheadline)
        case .ownGoal:
            Image(systemName: "soccerball").accessibilityHidden(true).font(.subheadline).foregroundStyle(Color.lossRed)
        case .yellowCard:
            RoundedRectangle(cornerRadius: 2).fill(.yellow).frame(width: 11, height: 15)
        case .redCard:
            RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 11, height: 15)
        case .secondYellow:
            ZStack {
                RoundedRectangle(cornerRadius: 2).fill(.yellow).frame(width: 11, height: 15).offset(x: -3, y: -2)
                RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 11, height: 15).offset(x: 3, y: 2)
            }
        case .injury:
            Image(systemName: "cross.case.fill").accessibilityHidden(true).foregroundStyle(.red).font(.caption)
        default:
            Image(systemName: "arrow.left.arrow.right").accessibilityHidden(true).foregroundStyle(Color.winGreen).font(.caption)
        }
    }

    // MARK: - Player of the match

    /// A whole screen for the player of the match. Tap for their profile.
    private func playerOfMatchScreen(_ potm: (player: Player, clubName: String, rating: Double), res: MatchResult) -> some View {
        let goals = res.goalEvents.filter { $0.playerId == potm.player.id && $0.type != .ownGoal }.count
        let assists = res.goalEvents.filter { $0.assistPlayerId == potm.player.id }.count
        return VStack(spacing: 18) {
            Text("Player of the Match")
                .font(.gfDisplay(26))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedStep, equals: .playerOfMatch)
                .padding(.top, 10)
            Button {
                profilePlayerId = potm.player.id
            } label: {
                VStack(spacing: 14) {
                    FaceView(player: potm.player, size: 130, style: .full)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: Color(hex: "FFC857").opacity(0.5), radius: 18)
                    Text(potm.player.fullName)
                        .font(.gfDisplay(26))
                        .multilineTextAlignment(.center)
                    Text("\(potm.player.primaryPosition.displayName) · \(potm.clubName) · Age \(potm.player.age)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "FFC857"))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 14) {
                        statChip(icon: "star.fill", text: String(format: "%.1f", potm.rating), highlight: true)
                        statChip(icon: "soccerball", text: "\(goals)", highlight: false)
                        statChip(icon: "shoe.fill", text: "\(assists)", highlight: false)
                    }
                    Label("Open profile", systemImage: "person.text.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RadialGradient(colors: [Color(hex: "FFC857").opacity(0.25), .clear], center: .top, startRadius: 5, endRadius: 320)
                )
                .gfCard(padding: 0)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(potm.player.fullName), \(potm.player.primaryPosition.displayName) for \(potm.clubName), age \(potm.player.age). Match rating \(String(format: "%.1f", potm.rating)). \(goals) \(goals == 1 ? "goal" : "goals"), \(assists) \(assists == 1 ? "assist" : "assists").")
            .accessibilityHint("Opens the player's profile")
            .accessibilityAddTraits(.isButton)
        }
        .frame(minHeight: 520)
    }

    // MARK: - Player of the match & ratings

    /// The man of the match in the spotlight: portrait, name, rating and
    /// goal contributions.
    private func potmCard(_ potm: (player: Player, clubName: String, rating: Double), res: MatchResult) -> some View {
        let goals = res.goalEvents.filter { $0.playerId == potm.player.id && $0.type != .ownGoal }.count
        let assists = res.goalEvents.filter { $0.assistPlayerId == potm.player.id }.count
        return Button {
            profilePlayerId = potm.player.id
        } label: {
            VStack(spacing: 10) {
                FaceView(player: potm.player, size: 76, style: .full)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color(hex: "D4AF37").opacity(0.5), radius: 14)
                Text(potm.player.fullName.uppercased())
                    .font(.gfDisplay(18))
                    .multilineTextAlignment(.center)
                Text("MATCH MVP · \(potm.clubName.uppercased())")
                    .font(.gfLabel(14))
                    .foregroundStyle(Color(hex: "D4AF37"))
                HStack(spacing: 14) {
                    statChip(icon: "star.fill", text: String(format: "%.1f", potm.rating), highlight: true)
                    if goals > 0 { statChip(icon: "soccerball", text: "\(goals)", highlight: false) }
                    if assists > 0 { statChip(icon: "shoe.fill", text: "\(assists)", highlight: false) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RadialGradient(colors: [Color(hex: "D4AF37").opacity(0.25), .clear], center: .top, startRadius: 5, endRadius: 260)
            )
            .gfCard(padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match MVP, \(potm.player.fullName), rating \(String(format: "%.1f", potm.rating))\(goals > 0 ? ", \(goals) goals" : "")\(assists > 0 ? ", \(assists) assists" : "")")
    }

    private func statChip(icon: String, text: String, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).accessibilityHidden(true).font(.caption)
            Text(text)
                .font(.gfLabel(13).monospacedDigit())
                .foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(highlight ? Color.gfMint : Color.white))
        }
    }

    @ViewBuilder
    private func ratingsCard(res: MatchResult) -> some View {
        if let club = gameState.userClub {
            let rated = club.players
                .compactMap { p in res.playerRatings[p.id].map { (player: p, rating: $0) } }
                .sorted { $0.rating > $1.rating }
            if !rated.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    GFSectionHeader(title: "Your Ratings", icon: "chart.bar.fill")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(rated, id: \.player.id) { entry in
                                VStack(spacing: 6) {
                                    FaceView(player: entry.player, size: 40)
                                    Text(entry.player.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                    Text(String(format: "%.1f", entry.rating))
                                        .font(.subheadline.weight(.heavy).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(ratingColor(entry.rating), in: Capsule())
                                }
                                .frame(width: 72)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.tertiarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .gfCard()
            }
        }
    }

    private func ratingColor(_ rating: Double) -> Color {
        switch rating {
        case 8...: return Color(hex: "1E8449")
        case 7..<8: return Color.winGreen
        case 6..<7: return Color.orange
        default: return Color.lossRed
        }
    }

    // MARK: - Stats

    private func statsCard(res: MatchResult, home: Club, away: Club) -> some View {
        let h = res.homeStats, a = res.awayStats
        let homeColor = Color(hex: home.primaryColor)
        let awayColor = Color(hex: away.primaryColor == home.primaryColor ? away.secondaryColor : away.primaryColor)
        return VStack(alignment: .leading, spacing: 14) {
            GFSectionHeader(title: "Match Stats", icon: "chart.xyaxis.line")
            DualStatBar(title: "Possession", home: h.possession, away: a.possession,
                        homeText: "\(Int(h.possession))%", awayText: "\(Int(a.possession))%", homeColor: homeColor, awayColor: awayColor)
            DualStatBar(title: "Expected goals", home: h.xG, away: a.xG,
                        homeText: String(format: "%.2f", h.xG), awayText: String(format: "%.2f", a.xG), homeColor: homeColor, awayColor: awayColor)
            DualStatBar(title: "Shots", home: Double(h.shots), away: Double(a.shots),
                        homeText: "\(h.shots)", awayText: "\(a.shots)", homeColor: homeColor, awayColor: awayColor)
            DualStatBar(title: "On target", home: Double(h.shotsOnTarget), away: Double(a.shotsOnTarget),
                        homeText: "\(h.shotsOnTarget)", awayText: "\(a.shotsOnTarget)", homeColor: homeColor, awayColor: awayColor)
            DualStatBar(title: "Corners", home: Double(h.corners), away: Double(a.corners),
                        homeText: "\(h.corners)", awayText: "\(a.corners)", homeColor: homeColor, awayColor: awayColor)
            DualStatBar(title: "Fouls", home: Double(h.fouls), away: Double(a.fouls),
                        homeText: "\(h.fouls)", awayText: "\(a.fouls)", homeColor: homeColor, awayColor: awayColor)
        }
        .gfCard()
    }

    // MARK: - Elsewhere

    @ViewBuilder
    private func elsewhereCard(fixture: Fixture) -> some View {
        let others = otherResultsThisWeek(for: fixture)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { showElsewhere.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait").accessibilityHidden(true).foregroundStyle(Color.accentColor)
                        Text("Elsewhere in Matchweek \(gameState.leagueRound(of: fixture))").font(.headline)
                        Spacer()
                        Text("\(others.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").accessibilityHidden(true)
                            .rotationEffect(.degrees(showElsewhere ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showElsewhere ? "Hides the other results" : "Shows the other results")
                if showElsewhere {
                    ForEach(others, id: \.fixture.id) { entry in
                        HStack {
                            Text(entry.homeName)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(entry.result.scoreText)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color(UIColor.tertiarySystemGroupedBackground), in: Capsule())
                            Text(entry.awayName)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .gfCard()
        }
    }

    /// The table around the user's club after a league match, or after a
    /// European league-phase match.
    @ViewBuilder
    private func tableCard(fixture: Fixture) -> some View {
        if let tieId = fixture.europeanFixtureId, let uid = gameState.userClubId,
           let state = gameState.europeanCompetitions.first(where: { $0.fixtures.contains { $0.id == tieId } }),
           let tie = state.fixtures.first(where: { $0.id == tieId }), tie.stage == "League Phase" {
            // Tonight's result counts straight away; the rest of the
            // matchweek is still to be played.
            let rows = gameState.europeanTable(state, including: tie.isPlayed ? nil : fixture)
            if !rows.isEmpty {
                EuropeanTableAround(title: state.competition.displayName, rows: rows, userClubId: uid,
                                    note: tie.isPlayed ? nil : "Other matches in this matchweek are still to be played.")
            }
        } else if let league = gameState.currentLeague, fixture.competition == league.name, let uid = gameState.userClubId {
            let table = gameState.currentLeagueStandings
            if let mine = table.firstIndex(where: { $0.clubId == uid }) {
                let lower = max(0, min(mine - 2, table.count - 5))
                let upper = min(table.count, lower + 5)
                VStack(spacing: 8) {
                    HStack {
                        Text("STANDINGS").font(.gfDisplay(18))
                        Spacer()
                        Text(league.name).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("#").frame(width: 26, alignment: .leading)
                        Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
                        Text("P").frame(width: 28)
                        Text("GD").frame(width: 34)
                        Text("PTS").frame(width: 34)
                    }
                    .font(.gfLabel(12))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    ForEach(lower..<upper, id: \.self) { i in
                        let row = table[i]
                        let club = gameState.club(withId: row.clubId)
                        HStack {
                            Text("\(i + 1)").frame(width: 26, alignment: .leading)
                            HStack(spacing: 6) {
                                if let club { CrestView(club: club, size: 18) }
                                Text(club?.name ?? "–").lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.played)").frame(width: 28)
                            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)").frame(width: 34)
                            Text("\(row.points)").frame(width: 34).fontWeight(.heavy)
                        }
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(row.clubId == uid ? .heavy : .regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(row.clubId == uid ? Color.white.opacity(0.14) : Color.clear))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(i + 1). \(club?.name ?? ""), played \(row.played), goal difference \(row.goalDifference), \(row.points) points")
                    }
                }
                .gfCard()
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                // Forget the finished match so the next match day selects the
                // next fixture, never this one again.
                gameState.closeFinishedMatch()
                gameState.currentScreen = .dashboard
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            // Just one button once the match is over: Continue.
        }
        .padding(.top, 4)
    }

    // MARK: - Data

    private func otherResultsThisWeek(for fixture: Fixture) -> [(fixture: Fixture, homeName: String, awayName: String, result: MatchResult)] {
        gameState.season.fixtures(forWeek: fixture.matchWeek)
            .filter { $0.isPlayed && $0.id != fixture.id && $0.competition == fixture.competition }
            .compactMap { f in
                guard let result = f.result,
                      let home = gameState.club(withId: f.homeClubId),
                      let away = gameState.club(withId: f.awayClubId) else { return nil }
                return (f, home.name, away.name, result)
            }
    }

    /// The engine's Player of the Match, or the highest-rated player.
    private func potmPlayer(for res: MatchResult) -> (player: Player, clubName: String, rating: Double)? {
        guard let id = res.manOfTheMatch ?? res.playerRatings.max(by: { $0.value < $1.value })?.key,
              let lookup = gameState.player(withId: id) else { return nil }
        return (lookup.player, lookup.club?.name ?? "Unknown", res.playerRatings[id] ?? 0)
    }
}
