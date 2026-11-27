//
//  HubViews.swift
//  Touchline
//
//  The manager's home: a short header, one line about the next match, a
//  grid of small tiles (each opens its own screen) and one button that moves
//  the career on. Everything that used to crowd the home screen now lives
//  on its own minimal screen.
//

import SwiftUI

// MARK: - Shared hub pieces

/// Adds a "Home" back button and an inline title to a screen opened from a hub.
struct HubScreenModifier: ViewModifier {
    @Environment(GameState.self) private var gameState
    let title: String

    func body(content: Content) -> some View {
        content
            .stadiumBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        gameState.currentScreen = .dashboard
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").accessibilityHidden(true)
                            Text("Home")
                        }
                    }
                    .accessibilityLabel("Back to home")
                }
            }
    }
}

extension View {
    func hubScreen(_ title: String) -> some View { modifier(HubScreenModifier(title: title)) }
}

/// A small square tile: icon over a short caption, optional badge.
struct HubTile: View {
    let title: String
    let icon: String
    var badge: Int = 0
    var highlight: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).accessibilityHidden(true)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(highlight ? Color(hex: "2EC4B6") : Color(hex: "E4573D")))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: highlight ? "1B4D52" : "14393F"), Color(hex: "0E2A2F")], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text("\(min(badge, 99))")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: -3, y: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) new" : title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Five small tiles per row.
struct HubGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            content()
        }
        .buttonStyle(.plain)
    }
}

/// "Arsenal (H) · Premier League · Sat 21 Sep" in one compact row.
struct NextMatchLine: View {
    @Environment(GameState.self) private var gameState
    let verb: String

    var body: some View {
        if let club = gameState.userClub {
            if let fixture = gameState.nextUserFixture,
               let opponentId = fixture.opponentId(for: club.id),
               let opponent = gameState.club(withId: opponentId) {
                let today = fixture.date == gameState.season.currentDate
                let venue = fixture.homeClubId == club.id ? "home" : "away"
                let round = fixture.cupRound.map { "\(fixture.competition), \($0)" } ?? fixture.competition
                HStack(spacing: 12) {
                    CrestView(club: opponent, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(today ? "MATCH DAY · vs \(opponent.name)" : "Next: vs \(opponent.name)")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(venue.capitalized) · \(round) · \(DashboardView.shortDate(fixture.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: today ? [Color(hex: "E4573D"), Color(hex: "A93424")] : [Color(hex: "1B4D52"), Color(hex: "0E2A2F")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(today ? Color.white : Color(hex: "FFC857")).frame(width: 4).padding(.vertical, 12)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(today
                    ? "Match day. \(verb) \(opponent.name), \(venue), \(round)."
                    : "Next match: \(opponent.name), \(venue), \(round), \(DashboardView.longDate(fixture.date)).")
            } else if !gameState.isEndOfSeason {
                Text("No fixtures left this season.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The single button at the bottom of a hub: title plus a short caption.
struct HubContinueLabel: View {
    let title: String
    var caption: String? = nil
    var body: some View {
        VStack(spacing: 1) {
            Text(title)
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(nil)
                    .opacity(0.85)
            }
        }
    }
}

// MARK: - Manager home

public struct DashboardView: View {
    @Environment(GameState.self) private var gameState
    @State private var showingCalendar = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                // The national team's match is waiting for its manager.
                if let due = gameState.dueInternationalMatch {
                    Button {
                        gameState.currentScreen = .international
                    } label: {
                        Label("\(gameState.managedNationalTeam?.name ?? "International") match day: \(due.tournament.title), \(due.fixture.stage)",
                              systemImage: "flag.2.crossed.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gfSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Pick the squad and play the match")
                }
                if gameState.isUnemployed {
                    Button {
                        gameState.generateJobOffers(maxCount: 5)
                        gameState.currentScreen = .jobOffers
                    } label: {
                        HubContinueLabel(title: "Find a Job",
                                         caption: gameState.jobOffers.isEmpty ? "You are out of work" : "\(gameState.jobOffers.count) clubs interested")
                    }
                    .buttonStyle(.gfPrimary)
                    Button {
                        gameState.advanceWhileUnemployed()
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    } label: {
                        HubContinueLabel(title: gameState.isEndOfSeason ? "Start New Season" : "Wait a Week",
                                         caption: gameState.managedNationalTeam.map { "Managing \($0.name)" } ?? "Let the offers come to you")
                    }
                    .buttonStyle(.gfOutline)
                    HubGrid {
                        tile("Profile", "person.crop.circle", .managerProfile)
                        tile("News", "newspaper.fill", .news)
                        tile("Jobs", "briefcase.fill", .jobOffers)
                        tile("Settings", "gearshape.fill", .settings)
                    }
                } else {
                    NextMatchLine(verb: "Play")
                    if gameState.isEndOfSeason, let review = gameState.lastSeasonReview {
                        Button {
                            gameState.showingSeasonReview = true
                        } label: {
                            Label("Season review ready", systemImage: "star.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gfSurface))
                        }
                        .buttonStyle(.plain)
                    }
                    managerTiles
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom) {
            if !gameState.isUnemployed {
                Button(action: primaryAction) {
                    HubContinueLabel(title: primaryTitle, caption: primaryCaption)
                }
                .buttonStyle(.gfPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .accessibilityLabel(primaryCaption.map { "\(primaryTitle). \($0)" } ?? primaryTitle)
            }
        }
        .stadiumBackground()
        .navigationTitle(gameState.userClub?.name ?? "Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The main menu lives at the top left.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    gameState.currentScreen = .mainMenu
                } label: {
                    Label("Main Menu", systemImage: "line.3.horizontal")
                }
                .accessibilityLabel("Main menu")
            }
        }
        .fullScreenCover(isPresented: Binding(get: { gameState.showingSeasonReview },
                                              set: { gameState.showingSeasonReview = $0 })) {
            if let review = gameState.lastSeasonReview {
                SeasonReviewScreen(review: review) {
                    gameState.showingSeasonReview = false
                    gameState.startNewSeason()
                    try? SaveManager.shared.autoSave(gameState: gameState)
                }
                .environment(gameState)
            }
        }
        .fullScreenCover(isPresented: $showingCalendar) {
            CalendarAdvanceView { _ in
                showingCalendar = false
                try? SaveManager.shared.autoSave(gameState: gameState)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if let club = gameState.userClub { CrestView(club: club, size: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.longDate(gameState.season.currentDate))
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let club = gameState.userClub else { return "\(gameState.manager.fullName) · Unemployed" }
        let table = gameState.currentLeagueStandings
        if let index = table.firstIndex(where: { $0.clubId == club.id }) {
            return "\(club.leagueTier.displayName) · \(index + 1)\(Self.ordinal(index + 1)) · \(table[index].points) pts"
        }
        return club.leagueTier.displayName
    }

    // MARK: Tiles

    private var hasEurope: Bool {
        gameState.europeanCompetitions.contains { comp in
            comp.fixtures.contains { $0.homeClubId == gameState.userClubId || $0.awayClubId == gameState.userClubId }
        }
    }

    /// A compact Home: the everyday screens, with the rest grouped under
    /// Competitions, Club and Manager.
    private var managerTiles: some View {
        HubGrid {
            Group {
                tile("Inbox", "tray.full.fill", .mailbox, badge: gameState.unreadMailCount)
                tile("Squad", "person.3.fill", .squad)
                tile("Transfers", "arrow.left.arrow.right", .transferHub)
                tile("Training", "figure.run", .training)
                NavigationLink {
                    HubGroupView(title: "Competitions", rows: [
                        .screen("League Table", "list.number", .standings),
                        .screen("Fixtures & Results", "calendar", .matchHistory),
                        .screen("Europe", "star.circle.fill", .europeanCompetitions),
                        .screen("News", "newspaper.fill", .news)
                    ])
                } label: { HubTile(title: "Competitions", icon: "list.number") }
                NavigationLink {
                    HubGroupView(title: "Club", rows: [
                        .screen("Trophy Cabinet & Records", "trophy.fill", .history),
                        .screen("Finances", "sterlingsign.circle.fill", .finances),
                        .screen("Staff", "person.2.badge.gearshape.fill", .staff),
                        .screen("Youth Academy", "figure.and.child.holdinghands", .youthAcademy),
                        .board
                    ])
                } label: { HubTile(title: "Club", icon: "building.2.fill") }
                NavigationLink {
                    HubGroupView(title: "Manager", rows: [
                        .screen("My Profile", "person.crop.circle", .managerProfile),
                        .screen(gameState.jobOffers.isEmpty ? "Job Offers" : "Job Offers (\(gameState.jobOffers.count))", "briefcase.fill", .jobOffers),
                        .screen("Settings", "gearshape.fill", .settings)
                    ])
                } label: { HubTile(title: "Manager", icon: "person.crop.circle", badge: gameState.jobOffers.count) }
            }
        }
    }

    private func tile(_ title: String, _ icon: String, _ screen: AppScreen, badge: Int = 0) -> some View {
        Button { gameState.currentScreen = screen } label: { HubTile(title: title, icon: icon, badge: badge) }
    }

    // MARK: Primary action

    private var primaryTitle: String {
        if gameState.isEndOfSeason { return "Start New Season" }
        if let fixture = gameState.todaysUserFixture, let opponent = opponent(of: fixture) {
            return "Play vs \(opponent.name)"
        }
        if gameState.nextUserFixture == nil { return "Finish Season" }
        return "Continue"
    }

    private var primaryCaption: String? {
        if gameState.isEndOfSeason { return "Season \(gameState.season.year) is over" }
        if let fixture = gameState.todaysUserFixture {
            return fixture.cupRound.map { "\(fixture.competition) · \($0)" } ?? "\(fixture.competition) · Matchweek \(gameState.leagueRound(of: fixture))"
        }
        if let fixture = gameState.nextUserFixture { return "To match day · \(DashboardView.shortDate(fixture.date))" }
        return nil
    }

    private func opponent(of fixture: Fixture) -> Club? {
        guard let club = gameState.userClub, let id = fixture.opponentId(for: club.id) else { return nil }
        return gameState.club(withId: id)
    }

    private func primaryAction() {
        if gameState.isEndOfSeason {
            // The season in review first; its button starts the next one.
            if gameState.lastSeasonReview != nil {
                gameState.showingSeasonReview = true
            } else {
                gameState.startNewSeason()
                try? SaveManager.shared.autoSave(gameState: gameState)
            }
        } else if gameState.todaysUserFixture != nil {
            // Today's fixture, freshly selected, so the last match can never reopen.
            if gameState.selectTodaysUserFixture() { gameState.currentScreen = .matchDay }
        } else if gameState.matchSettings.animateCalendar && gameState.nextUserFixture != nil {
            showingCalendar = true
        } else {
            // Stops on match day; the button then offers the match.
            gameState.continueToMatchDay()
        }
    }

    // MARK: Dates

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func longDate(_ s: String) -> String {
        guard let d = parser.date(from: s) else { return s }
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: d)
    }

    static func shortDate(_ s: String) -> String {
        guard let d = parser.date(from: s) else { return s }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    static func ordinal(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

// MARK: - Board & readiness (its own screen)

struct ManagerStatusView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            if let club = gameState.userClub {
                let starters = club.startingXIPlayers
                let available = starters.filter { $0.injury == nil && $0.suspendedMatches == 0 }
                let fitness = starters.isEmpty ? 0 : Int(starters.map(\.matchFitness).reduce(0, +) / Double(starters.count))
                let sharpness = starters.isEmpty ? 0 : Int(starters.map(\.sharpness).reduce(0, +) / Double(starters.count))
                Section("Board") {
                    LabeledContent("Status", value: gameState.jobSecurity.status)
                    LabeledContent("Confidence", value: "\(gameState.jobSecurity.boardConfidence)%")
                    if let target = gameState.boardTarget(for: club) {
                        let table = gameState.currentLeagueStandings
                        LabeledContent("Target", value: target.goal)
                        if let index = table.firstIndex(where: { $0.clubId == club.id }) {
                            let position = index + 1
                            LabeledContent("Now", value: "\(position)\(DashboardView.ordinal(position)) · \(position <= target.position ? "on track" : "behind")")
                        }
                    }
                }
                if let fixture = gameState.nextUserFixture, let id = fixture.opponentId(for: club.id),
                   let opponent = gameState.club(withId: id) {
                    Section("Next opponent") {
                        LabeledContent("Opponent", value: "\(opponent.name) (\(fixture.homeClubId == club.id ? "home" : "away"))")
                        LabeledContent("Date", value: DashboardView.shortDate(fixture.date))
                        LabeledContent("Their starting XI", value: String(format: "%.1f", opponent.startingXIAverageOverall))
                        LabeledContent("Your starting XI", value: String(format: "%.1f", club.startingXIAverageOverall))
                    }
                }
                Section("Match Readiness") {
                    LabeledContent("Starters available", value: "\(available.count) of \(starters.count)")
                    LabeledContent("Injured in the squad", value: "\(club.injuredPlayers.count)")
                    LabeledContent("Fitness", value: "\(fitness)%")
                    LabeledContent("Sharpness", value: "\(sharpness)%")
                }
                Section("Money") {
                    LabeledContent("Bank", value: Player.formatCurrency(club.finances.balance))
                    LabeledContent("Transfer budget", value: Player.formatCurrency(club.finances.transferBudget))
                    LabeledContent("Wage room", value: "\(Player.formatCurrency(club.finances.weeklyWageSurplus))/w")
                }
            }
        }
        .stadiumBackground()
        .navigationTitle("Board")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A short list of related screens, opened from a Home tile.
struct HubGroupView: View {
    @Environment(GameState.self) private var gameState

    enum Row {
        case screen(String, String, AppScreen)
        case board
    }

    let title: String
    let rows: [Row]

    var body: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .screen(let name, let icon, let screen):
                    Button {
                        gameState.currentScreen = screen
                    } label: {
                        Label(name, systemImage: icon)
                    }
                case .board:
                    NavigationLink {
                        ManagerStatusView()
                    } label: {
                        Label("Board", systemImage: "building.columns.fill")
                    }
                }
            }
        }
        .stadiumBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}