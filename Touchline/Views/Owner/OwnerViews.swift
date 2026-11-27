//
//  OwnerViews.swift
//  Touchline
//
//  The owner's career: a hub of small tiles, each opening one minimal
//  screen. The owner never picks the team; on match day they watch.
//

import SwiftUI

// MARK: - Owner hub

public struct OwnerCareerTabView: View {
    @Environment(GameState.self) private var gameState
    @State private var showingCalendar = false

    public var body: some View {
        if gameState.awaitingClubPurchase {
            ClubPurchaseView()
        } else {
            hub
        }
    }

    private var pendingDecisions: Int {
        var count = 0
        if gameState.pendingWinBonusRequest { count += 1 }
        if gameState.pendingRecordMoment != nil { count += 1 }
        if gameState.pendingOwnerDecision != nil { count += 1 }
        if gameState.pendingManagerRequest != nil { count += 1 }
        if gameState.pendingTakeover != nil { count += 1 }
        return count
    }

    private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                NextMatchLine(verb: "Watch")
                if pendingDecisions > 0 {
                    NavigationLink { OwnerBoardroomView() } label: {
                        Label("\(pendingDecisions) decision\(pendingDecisions == 1 ? "" : "s") waiting", systemImage: "exclamationmark.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.gfNight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gfBanner))
                    }
                    .buttonStyle(.plain)
                }
                if gameState.owner.isInAdministration {
                    Label("In administration: points deducted and a transfer embargo.", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lossRed)
                }
                tiles
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: primaryAction) {
                HubContinueLabel(title: primaryTitle, caption: primaryCaption)
            }
            .buttonStyle(.gfPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .accessibilityLabel(primaryCaption.map { "\(primaryTitle). \($0)" } ?? primaryTitle)
        }
        .stadiumBackground()
        .navigationTitle(gameState.userClub?.name ?? "Owner")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingCalendar) {
            CalendarAdvanceView { _ in
                showingCalendar = false
                gameState.checkOwnerWeeklyMilestones()
                try? SaveManager.shared.autoSave(gameState: gameState)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let club = gameState.userClub { CrestView(club: club, size: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(DashboardView.longDate(gameState.season.currentDate))
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
        guard let club = gameState.userClub else { return "" }
        let table = gameState.currentLeagueStandings
        let cash = Player.formatCurrency(club.finances.balance)
        if let index = table.firstIndex(where: { $0.clubId == club.id }) {
            return "\(club.leagueTier.displayName) · \(index + 1)\(DashboardView.ordinal(index + 1)) · Cash \(cash)"
        }
        return "\(club.leagueTier.displayName) · Cash \(cash)"
    }

    private var tiles: some View {
        HubGrid {
            Group {
                NavigationLink { OwnerBoardroomView() } label: {
                    HubTile(title: "Boardroom", icon: "building.columns.fill", badge: pendingDecisions)
                }
                screenTile("Inbox", "tray.full.fill", .mailbox, badge: gameState.unreadMailCount)
                screenTile("News", "newspaper.fill", .news)
                screenTile("Fixtures", "calendar", .matchHistory)
                screenTile("Table", "list.number", .standings)
                NavigationLink { OwnerSquadView() } label: { HubTile(title: "Squad", icon: "person.3.fill") }
                NavigationLink { OwnerManagerView() } label: { HubTile(title: "Manager", icon: "person.badge.key.fill") }
                NavigationLink { OwnerStaffView() } label: { HubTile(title: "Staff", icon: "person.2.badge.gearshape.fill") }
            }
            Group {
                NavigationLink { OwnerFansView() } label: { HubTile(title: "Fans", icon: "megaphone.fill") }
                NavigationLink { OwnerCommercialView() } label: {
                    HubTile(title: "Sponsors", icon: "handshake.fill", badge: gameState.pendingSponsorOffers.count)
                }
                NavigationLink { OwnerAccountsView() } label: { HubTile(title: "Accounts", icon: "chart.bar.doc.horizontal.fill") }
                NavigationLink { OwnerBankView() } label: { HubTile(title: "Bank", icon: "banknote.fill") }
                NavigationLink { OwnerFacilitiesView() } label: { HubTile(title: "Facilities", icon: "building.2.fill") }
            }
            Group {
                NavigationLink { OwnerPolicyView() } label: { HubTile(title: "Policy", icon: "slider.horizontal.3") }
                NavigationLink { OwnerLegacyView() } label: { HubTile(title: "Legacy", icon: "rosette") }
                screenTile("History", "trophy.fill", .history)
                screenTile("Settings", "gearshape.fill", .settings)
                screenTile("Menu", "house.fill", .mainMenu)
            }
        }
    }

    private func screenTile(_ title: String, _ icon: String, _ screen: AppScreen, badge: Int = 0) -> some View {
        Button { gameState.currentScreen = screen } label: { HubTile(title: title, icon: icon, badge: badge) }
    }

    // MARK: Continue

    private var primaryTitle: String {
        if gameState.isEndOfSeason { return "Plan New Season" }
        if let fixture = gameState.todaysUserFixture, let club = gameState.userClub,
           let id = fixture.opponentId(for: club.id), let opponent = gameState.club(withId: id) {
            return "Watch vs \(opponent.name)"
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

    private func primaryAction() {
        if gameState.isEndOfSeason {
            gameState.advanceOwnerWeek()
        } else if gameState.todaysUserFixture != nil {
            if gameState.selectTodaysUserFixture() { gameState.currentScreen = .liveMatch }
        } else if gameState.matchSettings.animateCalendar && gameState.nextUserFixture != nil {
            gameState.checkWinBonusRequest()
            showingCalendar = true
        } else {
            gameState.continueToMatchDay()
        }
    }
}

// MARK: - Shared owner helpers

/// A short alert bound to an optional message.
private struct MessageAlert: ViewModifier {
    let title: String
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

extension View {
    fileprivate func messageAlert(_ title: String, _ message: Binding<String?>) -> some View {
        modifier(MessageAlert(title: title, message: message))
    }

    /// Standard look for a pushed owner screen.
    fileprivate func ownerScreen(_ title: String) -> some View {
        self
            .stadiumBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private func moneyText(_ amount: Int) -> some View {
    Text((amount < 0 ? "−" : "") + Player.formatCurrency(abs(amount)))
        .monospacedDigit()
        .foregroundStyle(amount < 0 ? Color.lossRed : .primary)
}

private func moneyRow(_ label: String, _ amount: Int) -> some View {
    LabeledContent(label) { moneyText(amount) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(amount < 0 ? "minus " : "")\(Player.spokenCurrency(abs(amount)))")
}

private func managerFaceSeed(_ name: String) -> UInt64 {
    let parts = name.split(separator: " ")
    return ManagerProfile.generateSeed(first: String(parts.first ?? ""), last: String(parts.dropFirst().joined(separator: " ")))
}

// MARK: - Boardroom (decisions only)

struct OwnerBoardroomView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?
    @State private var confirmSale = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if gameState.isEndOfSeason, let review = gameState.lastSeasonReview {
                    SeasonReviewCard(review: review)
                }
                if let club = gameState.userClub {
                    snapshot(club)
                    decisions(club)
                }
            }
            .padding(14)
        }
        .ownerScreen("Boardroom")
        .messageAlert("Board Decision", $message)
        .confirmationDialog("Sell the club?", isPresented: $confirmSale, titleVisibility: .visible) {
            Button("Sell and choose a new club", role: .destructive) {
                gameState.sellClubAndShop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The money is yours. You then pick a club you can afford; what is left over becomes that club's cash.")
        }
    }

    /// The owner's quick read on the club before any decisions.
    private func snapshot(_ club: Club) -> some View {
        let owner = gameState.owner
        return VStack(alignment: .leading, spacing: 6) {
            GFSectionHeader(title: "Where the club stands", icon: "gauge.with.dots.needle.33percent")
            if let status = gameState.ownerTargetStatus {
                Text("League: \(status.position)\(DashboardView.ordinal(status.position)) of \(status.teams). Target \(owner.seasonObjective.rawValue.lowercased()): \(status.onTrack ? "on track" : "behind").")
                    .font(.subheadline)
            }
            Text("Cash \(Player.formatCurrency(club.finances.balance)) · debt \(Player.formatCurrency(owner.totalDebt)) · valuation \(Player.formatCurrency(gameState.clubValuation)).")
                .font(.caption).foregroundStyle(.secondary)
            Text("Supporters \(owner.supporterConfidence)% · manager \(owner.managerSatisfaction >= 70 ? "settled" : owner.managerSatisfaction >= 40 ? "wants more support" : "close to walking out").")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gfCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func decisions(_ club: Club) -> some View {
        let nothing = !gameState.pendingWinBonusRequest && gameState.pendingRecordMoment == nil
            && gameState.pendingOwnerDecision == nil && gameState.pendingManagerRequest == nil
            && gameState.pendingTakeover == nil
        if nothing {
            Text("No decisions waiting. Press Continue on the home screen to move on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gfCard()
        }

        if let offer = gameState.pendingTakeover {
            GFEventCard(title: "Takeover Bid", icon: "building.2.crop.circle.fill") {
                Text("\(offer.bidder.capitalized) offers \(Player.formatCurrency(offer.amount)). The club is valued at \(Player.formatCurrency(gameState.clubValuation)).")
                    .font(.subheadline)
                Text("Sell, and you choose another club to buy with the money.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Sell") { confirmSale = true }.buttonStyle(.gfSolid)
                    Button("Reject") { gameState.declineTakeover() }.buttonStyle(.gfOutline)
                }
            }
        }

        if gameState.pendingWinBonusRequest {
            GFEventCard(title: "Win Bonus Request", icon: "person.3.fill") {
                Text("The players want a bonus for every win: a share of their weekly wage.")
                    .font(.subheadline)
                ForEach([0, 10, 20], id: \.self) { pct in
                    Button {
                        message = gameState.answerWinBonus(percent: pct)
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    } label: {
                        GFChoiceRow(title: pct == 0 ? "No bonus" : "\(pct)% bonus",
                                    detail: pct == 0 ? "Saves money; some players will be unhappy"
                                        : "About \(Player.formatCurrency(gameState.winBonusCost(percent: pct))) per win")
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if let moment = gameState.pendingRecordMoment {
            GFEventCard(title: moment.title, icon: moment.icon) {
                Text(moment.detail).font(.subheadline)
                Button("OK") { gameState.pendingRecordMoment = nil }.buttonStyle(.gfOutline)
            }
        }

        if let decision = gameState.pendingOwnerDecision {
            GFEventCard(title: decision.headline, icon: "megaphone.fill") {
                Text(decision.detail).font(.subheadline)
                ForEach(OwnerDecisionChoice.allCases) { choice in
                    Button {
                        message = gameState.respondToFans(choice)
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    } label: {
                        GFChoiceRow(title: choice.rawValue, detail: choice.summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if let request = gameState.pendingManagerRequest {
            GFEventCard(title: "Transfer Request", icon: "person.crop.circle.badge.questionmark") {
                Text("\(club.manager) wants \(request.playerName) (\(request.position), rated \(request.rating)) from \(request.sellerName).")
                    .font(.subheadline)
                moneyRow("Fee", request.fee).font(.caption)
                moneyRow("Wage", request.wage).font(.caption)
                moneyRow("Club cash", club.finances.balance).font(.caption)
                HStack(spacing: 8) {
                    Button("Approve") {
                        message = gameState.approveManagerRequest()
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    }
                    .buttonStyle(.gfSolid)
                    Button("Decline") {
                        gameState.declineManagerRequest()
                        message = "You turned the request down. \(club.manager) is not pleased."
                    }
                    .buttonStyle(.gfDanger)
                }
            }
        }
    }
}

// MARK: - Club purchase (after a sale)

struct ClubPurchaseView: View {
    @Environment(GameState.self) private var gameState
    @State private var search = ""
    @State private var choice: ClubForSale?
    @State private var confirmRetire = false
    @State private var retirementFailed = false

    private var results: [ClubForSale] {
        let all = gameState.clubsForSale
        guard !search.isEmpty else { return Array(all.prefix(150)) }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.division.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Your money", value: Player.formatCurrency(gameState.owner.personalWealth))
                Text("Pick a club you can afford. What is left after the price becomes the club's cash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if results.isEmpty {
                Text(search.isEmpty ? "No club is cheap enough." : "No club matches that search.")
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { sale in
                Button { choice = sale } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(sale.name).fontWeight(.semibold)
                            Spacer()
                            Text(Player.formatCurrency(sale.price)).font(.subheadline.monospacedDigit())
                        }
                        Text("\(sale.division) · reputation \(sale.reputation) · keeps \(Player.formatCurrency(gameState.owner.personalWealth - sale.price))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("\(sale.name), \(sale.division), price \(Player.spokenCurrency(sale.price)), starts with \(Player.spokenCurrency(gameState.owner.personalWealth - sale.price))")
            }
            Section {
                Button("Retire instead", role: .destructive) { confirmRetire = true }
            }
        }
        .searchable(text: $search, prompt: "Club or division")
        .ownerScreen("Buy a Club")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { gameState.currentScreen = .mainMenu } label: { Image(systemName: "house") }
                    .accessibilityLabel("Main Menu")
            }
        }
        .confirmationDialog("Buy \(choice?.name ?? "")?",
                            isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }),
                            titleVisibility: .visible) {
            if let sale = choice {
                Button("Buy for \(Player.formatCurrency(sale.price))") {
                    gameState.buyClub(sale.clubId)
                    gameState.currentScreen = .dashboard
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let sale = choice {
                Text("\(sale.name) will start with \(Player.formatCurrency(gameState.owner.personalWealth - sale.price)) in the bank.")
            }
        }
        .confirmationDialog("Retire from football?", isPresented: $confirmRetire, titleVisibility: .visible) {
            Button("Retire and end this career", role: .destructive) {
                do {
                    try SaveManager.shared.deleteSave(for: .autoSave)
                    gameState.resetForNewCareer(mode: .createClub)
                    gameState.currentScreen = .mainMenu
                } catch {
                    retirementFailed = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not retire", isPresented: $retirementFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The autosave could not be deleted. Try again.")
        }
    }
}

// MARK: - Squad (ratings and evaluation)

struct OwnerSquadView: View {
    @Environment(GameState.self) private var gameState

    private struct Line {
        let category: PositionCategory
        let count: Int
        let starters: Int
        let minimum: Int
        let average: Double
        let leagueAverage: Double
        var verdict: (text: String, color: Color) {
            if count < minimum { return ("Thin: sign cover", Color.lossRed) }
            if average >= leagueAverage + 2 { return ("Strong", Color.winGreen) }
            if average <= leagueAverage - 2 { return ("Weak", Color.bronzeAccent) }
            return ("Par", .secondary)
        }
    }

    private func topAverage(_ club: Club, _ category: PositionCategory, _ n: Int) -> Double {
        let ratings = club.players.filter { $0.primaryPosition.category == category }.map(\.overall).sorted(by: >).prefix(n)
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    private func lines(_ club: Club) -> [Line] {
        let rivals = gameState.clubs.filter { $0.leagueTier == club.leagueTier && !$0.isUserClub }
        let spec: [(PositionCategory, Int, Int)] = [(.goalkeeper, 1, 2), (.defender, 4, 5), (.midfielder, 3, 5), (.forward, 3, 4)]
        return spec.map { category, starters, minimum in
            let others = rivals.map { topAverage($0, category, starters) }.filter { $0 > 0 }
            let leagueAverage = others.isEmpty ? 0 : others.reduce(0, +) / Double(others.count)
            return Line(category: category,
                        count: club.players.filter { $0.primaryPosition.category == category }.count,
                        starters: starters, minimum: minimum,
                        average: topAverage(club, category, starters), leagueAverage: leagueAverage)
        }
    }

    /// 1 = best squad rating in the division.
    private func divisionRank(_ club: Club) -> (rank: Int, of: Int) {
        let peers = gameState.clubs.filter { $0.leagueTier == club.leagueTier }
        let better = peers.filter { $0.squadAverageOverall > club.squadAverageOverall }.count
        return (better + 1, peers.count)
    }

    var body: some View {
        List {
            if let club = gameState.userClub {
                let rank = divisionRank(club)
                Section("Ratings") {
                    LabeledContent("Starting XI", value: String(format: "%.1f", club.startingXIAverageOverall))
                    LabeledContent("Whole squad", value: String(format: "%.1f", club.squadAverageOverall))
                    LabeledContent("In your division", value: "\(rank.rank)\(DashboardView.ordinal(rank.rank)) of \(rank.of)")
                    LabeledContent("Injured", value: "\(club.injuredPlayers.count)")
                }
                Section(header: Text("Evaluation"), footer: Text("Compared with the average club in your division, line by line.")) {
                    ForEach(lines(club), id: \.category) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.category.displayName + "s").font(.subheadline.weight(.semibold))
                                Text("\(line.count) players · top \(line.starters) average \(String(format: "%.1f", line.average))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(line.verdict.text).font(.caption.weight(.semibold)).foregroundStyle(line.verdict.color)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    let ageAverage = Double(club.players.reduce(0) { $0 + $1.age }) / Double(max(1, club.players.count))
                    LabeledContent("Average age", value: String(format: "%.1f", ageAverage))
                    LabeledContent("Squad size", value: "\(club.players.count)")
                    LabeledContent("Players over 31", value: "\(club.players.filter { $0.age > 31 }.count)")
                    LabeledContent("Under 21", value: "\(club.players.filter { $0.age < 21 }.count)")
                }
                Section("Money") {
                    moneyRow("Squad market value", club.players.reduce(0) { $0 + $1.value })
                    moneyRow("Player wages a week", club.totalPlayerWageBill)
                    let expiring = club.players.filter { !$0.isOnLoan && ($0.contract?.yearsRemaining ?? 99) <= 1 }
                    LabeledContent("Contracts ending within a year", value: "\(expiring.count)")
                    ForEach(club.players.sorted { $0.payrollWage > $1.payrollWage }.prefix(3)) { player in
                        LabeledContent(player.fullName, value: "\(Player.formatCurrency(player.payrollWage))/w")
                    }
                }
                Section("Players (\(club.players.count))") {
                    ForEach(club.players.sorted { $0.overall > $1.overall }) { player in
                        NavigationLink(destination: PlayerDetailView(playerId: player.id)) {
                            PlayerRowView(player: player)
                        }
                    }
                }
            }
        }
        .ownerScreen("Squad")
    }
}

// MARK: - Manager

struct OwnerManagerView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?
    @State private var confirmSack = false

    var body: some View {
        List {
            if let club = gameState.userClub {
                Section {
                    LabeledContent("Manager", value: club.manager)
                    LabeledContent("Coaching rating", value: "\(gameState.owner.managerRating)")
                    LabeledContent("Mood", value: gameState.owner.managerSatisfaction >= 70 ? "Fully backed"
                                   : gameState.owner.managerSatisfaction >= 40 ? "Wants more support" : "Close to walking out")
                }
                Section("Season target") {
                    LabeledContent("Target", value: gameState.owner.seasonObjective.rawValue)
                    if let status = gameState.ownerTargetStatus {
                        LabeledContent("Now", value: "\(status.position)\(DashboardView.ordinal(status.position)) of \(status.teams) · \(status.onTrack ? "on track" : "behind")")
                            .foregroundStyle(status.onTrack ? Color.winGreen : Color.bronzeAccent)
                    }
                }
                if let contract = gameState.owner.managerContract {
                    Section("Contract") {
                        LabeledContent("Age", value: "\(contract.age)")
                        LabeledContent("Personality", value: contract.personality.rawValue)
                        LabeledContent("Years left", value: contract.yearsRemaining <= 0 ? "Expired" : "\(contract.yearsRemaining)")
                        LabeledContent("Wage", value: "\(Player.formatCurrency(contract.weeklyWage))/w")
                        LabeledContent("Cost to sack", value: Player.formatCurrency(contract.severance))
                        if contract.yearsRemaining <= 1, let ask = gameState.managerRenewalWage {
                            Text("Wants \(Player.formatCurrency(ask))/w to extend.").font(.caption)
                            HStack {
                                ForEach([1, 2, 3], id: \.self) { years in
                                    Button("+\(years) yr") {
                                        message = gameState.renewManagerContract(years: years)
                                            ? "\(contract.managerName) has signed a new contract."
                                            : "\(contract.managerName) turned the offer down."
                                        try? SaveManager.shared.autoSave(gameState: gameState)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("Manager shortlist") { OwnerShortlistView() }
                    if club.manager != "Interim Manager" {
                        Button("Dismiss Manager", role: .destructive) { confirmSack = true }
                    }
                }
            }
        }
        .ownerScreen("Manager")
        .messageAlert("Manager", $message)
        .confirmationDialog("Dismiss \(gameState.userClub?.manager ?? "manager")?", isPresented: $confirmSack, titleVisibility: .visible) {
            Button("Dismiss", role: .destructive) {
                let ok = gameState.dismissManager()
                message = ok ? "The manager has gone. Appoint a successor from the shortlist." : "The club cannot pay the compensation."
                if ok { try? SaveManager.shared.autoSave(gameState: gameState) }
            }
        } message: {
            Text("Costs \(Player.formatCurrency(gameState.owner.managerContract?.severance ?? 250_000)) in compensation.")
        }
    }
}

struct OwnerShortlistView: View {
    @Environment(GameState.self) private var gameState
    @State private var candidate: ManagerCandidate?
    @State private var message: String?

    var body: some View {
        List {
            Section(footer: Text("The shortlist changes every season.")) {
                ForEach(gameState.managerShortlist) { person in
                    Button { candidate = person } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(person.name).fontWeight(.semibold)
                                Spacer()
                                Text("Rep \(person.reputation)").font(.caption.monospacedDigit())
                            }
                            Text("\(person.style) · age \(person.age) · \(person.personality.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(Player.formatCurrency(person.wage))/w · compensation \(Player.formatCurrency(person.compensation))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Offers this candidate the job")
                }
            }
        }
        .ownerScreen("Shortlist")
        .messageAlert("Appointment", $message)
        .confirmationDialog("Contract for \(candidate?.name ?? "")",
                            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
                            titleVisibility: .visible) {
            if let person = candidate {
                ForEach([1, 2, 3, 4], id: \.self) { years in
                    Button("\(years)-year contract") {
                        let ok = gameState.appointManager(person, years: years)
                        message = ok ? "\(person.name) has accepted." : "The club cannot afford this appointment."
                        if ok { try? SaveManager.shared.autoSave(gameState: gameState) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Staff

struct OwnerStaffView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            if let club = gameState.userClub {
                ForEach(StaffRole.allCases) { role in
                    let team = club.staff.filter { $0.role == role }
                    Section(role.displayName) {
                        if team.isEmpty {
                            Text("Vacant").foregroundStyle(.secondary)
                        }
                        ForEach(team) { member in
                            LabeledContent(member.name, value: "quality \(member.quality) of 5 · \(Player.formatCurrency(member.wage))/w")
                        }
                        NavigationLink("Find candidates") { StaffMarketView(role: role) }
                    }
                }
            }
        }
        .ownerScreen("Staff")
    }
}

/// Candidates for one backroom role, refreshed monthly.
struct StaffMarketView: View {
    @Environment(GameState.self) private var gameState
    let role: StaffRole
    @State private var choice: StaffCandidate?
    @State private var message: String?

    var body: some View {
        List {
            if let club = gameState.userClub {
                let current = club.staff.filter { $0.role == role }
                Section(footer: Text("\(role.roleDescription) New names appear every month. Better clubs attract better staff.")) {
                    LabeledContent("Club cash", value: Player.formatCurrency(club.finances.balance))
                    if Club.staffLimit(role) == 1, let holder = current.first {
                        LabeledContent("Current", value: "\(holder.name), quality \(holder.quality) of 5")
                    } else {
                        LabeledContent("Employed", value: "\(current.count) of \(Club.staffLimit(role))")
                    }
                }
                Section("Available") {
                    ForEach(club.staffCandidates(role: role, seasonYear: gameState.season.year, week: gameState.season.currentWeek)) { person in
                        Button { choice = person } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(person.name).fontWeight(.semibold)
                                    Spacer()
                                    Text("Quality \(person.quality) of 5").foregroundStyle(Color.goldAccent)
                                }
                                Text("\(person.specialty) · age \(person.age)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(Player.formatCurrency(person.wage))/w · fee \(Player.formatCurrency(person.fee))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("\(person.name), \(person.quality) stars, \(person.specialty), age \(person.age), \(Player.spokenCurrency(person.wage)) a week, fee \(Player.spokenCurrency(person.fee))")
                    }
                }
            }
        }
        .ownerScreen(role.displayName)
        .messageAlert("Staff", $message)
        .confirmationDialog("Hire \(choice?.name ?? "")?",
                            isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }),
                            titleVisibility: .visible) {
            if let person = choice {
                Button("Hire for \(Player.formatCurrency(person.fee))") {
                    guard let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
                    message = gameState.clubs[idx].hire(person)
                    try? SaveManager.shared.autoSave(gameState: gameState)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Fans

struct OwnerFansView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            let mood = gameState.owner.supporterConfidence
            Section {
                LabeledContent("Supporter confidence", value: "\(mood)%")
                ProgressView(value: Double(mood), total: 100)
                    .tint(mood >= 60 ? Color.winGreen : mood >= 35 ? Color.orange : Color.lossRed)
                Text(mood >= 75 ? "The stands are bouncing." : mood >= 50 ? "Broadly content."
                     : mood >= 30 ? "Grumbles in the stands." : "Open revolt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Why") {
                if gameState.fanMoodReasons.isEmpty {
                    Text("Nothing has moved the fans yet this season.").foregroundStyle(.secondary)
                }
                ForEach(gameState.fanMoodReasons.prefix(6), id: \.reason) { entry in
                    LabeledContent(entry.reason, value: entry.change > 0 ? "+\(entry.change)" : "\(entry.change)")
                }
            }
            Section(header: Text("Ticket prices"), footer: Text(gameState.owner.ticketPricing.summary)) {
                Picker("Ticket prices", selection: Binding(get: { gameState.owner.ticketPricing },
                                                           set: { gameState.owner.ticketPricing = $0 })) {
                    ForEach(TicketPricing.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .ownerScreen("Fans")
    }
}

// MARK: - Sponsors

struct OwnerCommercialView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?

    var body: some View {
        List {
            if let club = gameState.userClub {
                Section(header: Text("Partners (\(gameState.owner.sponsorshipDeals.count) of 3)")) {
                    if gameState.owner.sponsorshipDeals.isEmpty {
                        Text("No partners yet.").foregroundStyle(.secondary)
                    }
                    ForEach(gameState.owner.sponsorshipDeals) { deal in
                        LabeledContent(deal.sponsorName, value: "\(Player.formatCurrency(deal.annualValue))/yr · \(deal.yearsRemaining) yr")
                    }
                }
                Section(header: Text("Offers"), footer: Text("Sponsors come to you. Bigger brands only talk to clubs in higher divisions with a bigger name. Offers lapse after four weeks.")) {
                    if gameState.pendingSponsorOffers.isEmpty {
                        Text("No offers on the table.").foregroundStyle(.secondary)
                    }
                    ForEach(gameState.pendingSponsorOffers) { offer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(offer.sponsorName).fontWeight(.semibold)
                            Text("\(offer.tier.rawValue) · \(Player.formatCurrency(offer.annualValue))/yr · \(offer.years) yr")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Accept") { message = gameState.acceptSponsorOffer(offer.id) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(gameState.sponsorSlotsFree == 0)
                                Button("Decline") { gameState.declineSponsorOffer(offer.id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section(footer: Text("Who will talk to you: \(gameState.availableSponsorTiers.map { $0.rawValue.lowercased() }.joined(separator: ", ")).")) {
                    Button("Brief an agency (\(Player.formatCurrency(SponsorMarket.agencyFee(level: club.leagueTier.level))))") {
                        message = gameState.hireSponsorAgency()
                    }
                    .disabled(gameState.sponsorAgencyCooldown > 0 || gameState.sponsorSlotsFree == 0)
                }
                Section(header: Text("Stadium naming rights"), footer: Text("Supporters dislike losing the ground's name.")) {
                    if let value = gameState.owner.namingRightsValue {
                        LabeledContent(club.stadium, value: "\(Player.formatCurrency(value))/yr")
                    } else {
                        Button("Sell for \(Player.formatCurrency(OwnerBusiness.namingRightsValue(capacity: club.stadiumCapacity, reputation: club.reputation)))/yr") {
                            message = gameState.signNamingRights() ? "The stadium has a new name." : "The deal could not be agreed."
                            try? SaveManager.shared.autoSave(gameState: gameState)
                        }
                    }
                }
            }
        }
        .ownerScreen("Sponsors")
        .messageAlert("Commercial", $message)
    }
}

// MARK: - Accounts

struct OwnerAccountsView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            if let club = gameState.userClub {
                let owner = gameState.owner
                Section("Value") {
                    moneyRow("Valuation", gameState.clubValuation)
                    if let start = owner.valuationAtTakeover, start > 0 {
                        let change = Int((Double(gameState.clubValuation) / Double(start) - 1) * 100)
                        LabeledContent("Since you took over", value: "\(change >= 0 ? "+" : "")\(change)%")
                    }
                    moneyRow("Cash", club.finances.balance)
                    moneyRow("Bank debt", owner.totalDebt)
                }
                let turnover = OwnerBusiness.annualRevenue(club.finances)
                if turnover > 0 {
                    let wageRatio = Int((Double(club.totalWeeklyWageBill * 52) / Double(turnover) * 100).rounded())
                    Section(header: Text("Financial health"), footer: Text(wageRatio > 80 ? "Wages swallow most of the income. Banks and the league will take notice."
                                                                         : wageRatio > 65 ? "Wages are high for the turnover. Be careful." : "Wages are in a healthy range.")) {
                        LabeledContent("Wages to turnover", value: "(wageRatio)%")
                            .foregroundStyle(wageRatio > 80 ? Color.lossRed : wageRatio > 65 ? Color.bronzeAccent : .primary)
                        moneyRow("Turnover (a year)", turnover)
                        moneyRow("Dividends taken", owner.dividendsTaken)
                    }
                }
                if let flow = gameState.weeklyCashFlow {
                    Section(header: Text("Last week"), footer: Text(flow.advice)) {
                        moneyRow("TV & prize money", flow.broadcasting)
                        moneyRow("Sponsors & merchandise", flow.commercial)
                        moneyRow("Tickets", flow.matchday)
                        moneyRow("Wages", -flow.wages)
                        moneyRow("Running costs", -flow.running)
                        if flow.loanRepayments > 0 { moneyRow("Loan repayments", -flow.loanRepayments) }
                        moneyRow("Net", flow.net).fontWeight(.bold)
                        moneyRow("Forecast season end", flow.projectedBalance)
                    }
                }
                if let ledger = gameState.seasonLedger {
                    Section("This season") {
                        moneyRow("Broadcasting", ledger.broadcasting)
                        moneyRow("Commercial", ledger.commercial)
                        moneyRow("Merchandise", ledger.merchandise)
                        moneyRow("Matchday", ledger.matchday)
                        moneyRow("Prize money", ledger.prizeMoney)
                        moneyRow("Player sales", ledger.playerSales)
                        moneyRow("Owner investment", ledger.ownerInvestment)
                        moneyRow("Wages", -ledger.wages)
                        moneyRow("Transfer fees", -ledger.transfers)
                        moneyRow("Other", ledger.other(currentBalance: club.finances.balance))
                        moneyRow("Operating profit", ledger.operatingProfit).fontWeight(.semibold)
                    }
                }
                if !owner.seasonHistory.isEmpty {
                    Section("Your seasons") {
                        ForEach(owner.seasonHistory.reversed()) { record in
                            LabeledContent(record.seasonYear,
                                           value: "\(record.finalPosition)\(DashboardView.ordinal(record.finalPosition)) · \(record.won)W \(record.drawn)D \(record.lost)L")
                        }
                    }
                }
            }
        }
        .ownerScreen("Accounts")
    }
}

// MARK: - Bank

struct OwnerBankView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?

    var body: some View {
        List {
            let owner = gameState.owner
            Section("You") {
                moneyRow("Your money", owner.personalWealth)
                moneyRow("Invested so far", owner.totalInvested)
                if owner.isInAdministration {
                    Label("In administration until the books balance.", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(Color.lossRed)
                } else if owner.weeksInDebt > 0 {
                    Label("Overdrawn for \(owner.weeksInDebt) week\(owner.weeksInDebt == 1 ? "" : "s"). Ten means administration.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.bronzeAccent)
                }
            }
            Section(header: Text("Invest"), footer: Text("Goes into club cash.")) {
                ForEach([250_000, 1_000_000, 5_000_000, 20_000_000], id: \.self) { amount in
                    Button("Invest \(Player.formatCurrency(amount))") {
                        message = gameState.investInClub(amount) ? "\(Player.formatCurrency(amount)) invested." : "You do not have that much."
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    }
                    .disabled(amount > owner.personalWealth)
                }
            }
            Section(header: Text("Dividend"), footer: Text("Only a debt-free club with cash to spare can pay one. Supporters and the manager do not like seeing money leave.")) {
                let dividend = gameState.maxDividend
                Button("Take (Player.formatCurrency(dividend)) from the club") {
                    message = gameState.takeDividend(dividend) ? "(Player.formatCurrency(dividend)) paid to you." : "The club cannot afford a dividend."
                    try? SaveManager.shared.autoSave(gameState: gameState)
                }
                .disabled(dividend < 100_000)
            }
            Section(header: Text("Loans"), footer: Text("Repaid weekly over two seasons. The more the club owes, the higher the rate.")) {
                ForEach(owner.loans) { loan in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Player.formatCurrency(loan.principal)) at \(Int((loan.rate * 100).rounded()))%")
                            Text("\(Player.formatCurrency(loan.remaining)) left · \(Player.formatCurrency(loan.weeklyRepayment))/w")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Repay") {
                            message = gameState.repayLoan(id: loan.id) ? "Loan repaid." : "Not enough cash."
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if gameState.loanOffers.isEmpty {
                    Text(owner.isInAdministration ? "Banks will not lend to a club in administration." : "The bank will not lend any more.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(gameState.loanOffers.enumerated()), id: \.offset) { _, offer in
                    Button("Borrow \(Player.formatCurrency(offer.amount)) at \(Int((offer.rate * 100).rounded()))%") {
                        message = gameState.takeLoan(amount: offer.amount, rate: offer.rate) ? "Loan agreed." : "The bank declined."
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    }
                }
            }
        }
        .ownerScreen("Bank")
        .messageAlert("Bank", $message)
    }
}

// MARK: - Facilities

/// Training ground, academy, medical centre and the stadium in one place.
struct OwnerFacilitiesView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            if let club = gameState.userClub {
                Section {
                    NavigationLink { OwnerFacilityView(area: .training) } label: {
                        LabeledContent("Training ground", value: "Level (club.trainingFacilityLevel)")
                    }
                    NavigationLink { OwnerFacilityView(area: .academy) } label: {
                        LabeledContent("Youth academy", value: "Level (club.youthAcademyLevel)")
                    }
                    NavigationLink { OwnerFacilityView(area: .medical) } label: {
                        LabeledContent("Medical centre", value: "Level (club.medicalFacilityLevel)")
                    }
                    NavigationLink { OwnerStadiumView() } label: {
                        LabeledContent("Stadium", value: club.stadiumCapacity.formatted())
                    }
                }
            }
        }
        .ownerScreen("Facilities")
    }
}

struct OwnerFacilityView: View {
    @Environment(GameState.self) private var gameState
    enum Area { case training, academy, medical }
    let area: Area
    @State private var message: String?

    var body: some View {
        List {
            if let club = gameState.userClub {
                let info = details(club)
                Section(footer: Text(info.detail)) {
                    LabeledContent("Level", value: "\(info.level) of 5")
                    ProgressView(value: Double(info.level), total: 5).tint(Color.gfMint)
                }
                Section("Now") {
                    ForEach(info.benefits(info.level), id: \.self) { Text($0) }
                }
                if info.level < 5 {
                    Section("Next level") {
                        ForEach(info.benefits(info.level + 1), id: \.self) { Text($0) }
                        Button("Upgrade for \(Player.formatCurrency(info.cost))") { upgrade() }
                            .disabled(info.budget < info.cost)
                        Text("Paid from \(info.budgetName): \(Player.formatCurrency(info.budget))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if area == .medical {
                    Section("How you compare") {
                        ForEach(gameState.facilityComparison) { item in
                            LabeledContent(item.name, value: "\(item.rank)\(DashboardView.ordinal(item.rank)) of \(item.of)")
                        }
                    }
                }
            }
        }
        .ownerScreen(title)
        .messageAlert("Facilities", $message)
    }

    private var title: String {
        switch area {
        case .training: return "Training Ground"
        case .academy: return "Youth Academy"
        case .medical: return "Medical Centre"
        }
    }

    private func details(_ club: Club) -> (level: Int, detail: String, cost: Int, budget: Int, budgetName: String, benefits: (Int) -> [String]) {
        switch area {
        case .training:
            return (club.trainingFacilityLevel, "Pitches, coaching and sports science.", club.trainingUpgradeCost,
                    club.finances.transferBudget, "transfer budget", { level in
                        switch level {
                        case ...1: return ["Young players develop slowly"]
                        case 2...3: return ["Standard development"]
                        case 4: return ["15% chance of an extra +1 rating a season (players under 82)"]
                        default: return ["30% chance of an extra +1 rating a season (players under 82)"]
                        }
                    })
        case .academy:
            return (club.youthAcademyLevel, "Scouting, coaching and housing for teenagers.", club.academyUpgradeCost,
                    club.finances.transferBudget, "transfer budget", { level in
                        ["Intake quality: \(["Poor", "Basic", "Decent", "Good", "Excellent"][max(0, min(4, level - 1))])"]
                    })
        case .medical:
            return (club.medicalFacilityLevel, "Physios, surgeons and recovery rooms.", club.medicalUpgradeCost,
                    club.finances.balance, "cash", { level in ["Injury prevention level \(level)", "Faster recovery"] })
        }
    }

    private func upgrade() {
        guard let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        let ok: Bool
        switch area {
        case .training: ok = gameState.clubs[idx].upgradeTrainingGround()
        case .academy: ok = gameState.clubs[idx].upgradeYouthAcademy()
        case .medical: ok = gameState.clubs[idx].upgradeMedicalFacilities()
        }
        message = ok ? "Upgrade approved." : "The club cannot fund this right now."
        if ok { try? SaveManager.shared.autoSave(gameState: gameState) }
    }
}

struct OwnerStadiumView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?

    var body: some View {
        List {
            if let club = gameState.userClub {
                Section {
                    LabeledContent("Ground", value: club.stadium)
                    LabeledContent("Capacity", value: club.stadiumCapacity.formatted())
                    LabeledContent("Cash", value: Player.formatCurrency(club.finances.balance))
                }
                Section(footer: Text("Adds about 15% capacity.")) {
                    Button("Expand for \(Player.formatCurrency(club.stadiumExpansionCost))") {
                        guard let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
                        let ok = gameState.clubs[idx].expandStadium()
                        message = ok ? "Capacity is now \(gameState.clubs[idx].stadiumCapacity.formatted())." : "The club cannot fund this."
                        if ok { try? SaveManager.shared.autoSave(gameState: gameState) }
                    }
                    .disabled(club.finances.balance < club.stadiumExpansionCost)
                }
                if let project = gameState.owner.stadiumProject {
                    Section("New stadium") {
                        ProgressView(value: project.progress).tint(Color.gfMint)
                        Text("\(project.newCapacity.formatted()) seats · opens in \(project.weeksRemaining) week\(project.weeksRemaining == 1 ? "" : "s")")
                            .font(.caption)
                    }
                } else if let plan = gameState.newStadiumPlan {
                    Section(header: Text("New stadium"), footer: Text("A year-long build paid from club cash.")) {
                        Button("Build \(plan.capacity.formatted()) seats for \(Player.formatCurrency(plan.cost))") {
                            message = gameState.startStadiumProject() ? "Construction has begun." : "The club needs \(Player.formatCurrency(plan.cost)) in cash."
                        }
                    }
                }
            }
        }
        .ownerScreen("Stadium")
        .messageAlert("Stadium", $message)
    }
}

// MARK: - Identity

struct OwnerIdentityView: View {
    @Environment(GameState.self) private var gameState
    @State private var stadiumName = ""
    @State private var message: String?

    private static let palette: [(name: String, hex: String)] = [
        ("Red", "#C8102E"), ("Claret", "#7A263A"), ("Sky", "#6CABDD"), ("Royal", "#034694"), ("Navy", "#132257"),
        ("Green", "#00A650"), ("Gold", "#FDB913"), ("Orange", "#F18A01"), ("Black", "#111111"), ("White", "#FFFFFF"),
        ("Purple", "#5C2D91"), ("Maroon", "#800000")
    ]

    var body: some View {
        List {
            if let club = gameState.userClub {
                Section(footer: Text(gameState.owner.namingRightsValue != nil ? "The name belongs to your naming-rights sponsor." : "")) {
                    HStack {
                        TextField("Stadium name", text: $stadiumName)
                            .textInputAutocapitalization(.words)
                        Button("Rename") {
                            message = gameState.renameStadium(stadiumName) ? "The stadium is now \(stadiumName)." : "Use up to 40 characters."
                            try? SaveManager.shared.autoSave(gameState: gameState)
                        }
                        .disabled(stadiumName.trimmingCharacters(in: .whitespaces).isEmpty || stadiumName == club.stadium)
                    }
                    .disabled(gameState.owner.namingRightsValue != nil)
                    .onAppear { stadiumName = club.stadium }
                }
                Section("Colours") {
                    colourPicker("Home", selected: club.primaryColor) { gameState.setClubColours(primary: $0, secondary: club.secondaryColor) }
                    colourPicker("Second", selected: club.secondaryColor) { gameState.setClubColours(primary: club.primaryColor, secondary: $0) }
                }
                Section(footer: Text(gameState.owner.vision.summary)) {
                    Picker("Vision", selection: Binding(get: { gameState.owner.vision }, set: {
                        gameState.owner.vision = $0
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    })) {
                        ForEach(ClubVision.allCases) { Text($0.rawValue).tag($0) }
                    }
                    LabeledContent("City", value: club.city)
                    LabeledContent("Reputation", value: "\(club.reputation)/100")
                }
            }
        }
        .ownerScreen("Identity")
        .messageAlert("Club", $message)
    }

    private func colourPicker(_ title: String, selected: String, apply: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OwnerIdentityView.palette, id: \.hex) { colour in
                        let chosen = selected.uppercased() == colour.hex
                        Button {
                            apply(colour.hex)
                            try? SaveManager.shared.autoSave(gameState: gameState)
                        } label: {
                            Circle()
                                .fill(Color(hex: colour.hex))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary.opacity(chosen ? 0.9 : 0.15), lineWidth: chosen ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(colour.name)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
        }
    }
}

// MARK: - Policy

struct OwnerPolicyView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        List {
            let owner = gameState.owner
            Section(header: Text("Budget split"), footer: Text("Wages get \(owner.budgetAllocation.wageBudgetPercent)%.")) {
                Text("Transfers: \(owner.budgetAllocation.transferBudgetPercent)%")
                Slider(value: Binding(get: { Double(gameState.owner.budgetAllocation.transferBudgetPercent) },
                                      set: { _ = gameState.setOwnerBudgetAllocation(transferPercent: Int($0.rounded())) }),
                       in: 20...80, step: 5)
                    .accessibilityLabel("Transfer share")
                    .accessibilityValue("\(owner.budgetAllocation.transferBudgetPercent) percent")
            }
            Section(header: Text("Manager's spending authority"), footer: Text("Bigger signings need your approval.")) {
                Stepper("Up to \(owner.delegatedSpendPercent)% without asking",
                        value: Binding(get: { gameState.owner.delegatedSpendPercent }, set: { gameState.owner.delegatedSpendPercent = $0 }),
                        in: 0...100, step: 5)
            }
            Section(header: Text("Season target"), footer: Text(owner.seasonObjective.summary + " Judged at the end of the season.")) {
                Picker("Target", selection: Binding(get: { gameState.owner.seasonObjective }, set: { gameState.owner.seasonObjective = $0 })) {
                    ForEach(SeasonObjective.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section(header: Text("Recruitment"), footer: Text(owner.recruitmentPolicy.summary)) {
                Picker("Policy", selection: Binding(get: { gameState.owner.recruitmentPolicy }, set: { gameState.owner.recruitmentPolicy = $0 })) {
                    ForEach(RecruitmentPolicy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink("Club identity: name, colours, vision") { OwnerIdentityView() }
            }
        }
        .ownerScreen("Policy")
    }
}

// MARK: - Legacy

struct OwnerLegacyView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?

    var body: some View {
        List {
            Section(footer: Text("Earn points by running the club well, then spend them on board decisions.")) {
                LabeledContent("Legacy points", value: "\(gameState.owner.legacyPoints)")
            }
            Section("Spend") {
                ForEach(OwnerInvestment.allCases) { investment in
                    Button {
                        let ok = gameState.approveOwnerInvestment(investment)
                        message = ok ? "\(investment.title) approved." : "You need \(investment.cost) points."
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(investment.title) · \(investment.cost) pts").fontWeight(.semibold)
                            Text(investment.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(gameState.owner.legacyPoints < investment.cost)
                }
            }
            Section("Milestones") {
                ForEach(gameState.owner.milestones) { milestone in
                    HStack {
                        Image(systemName: milestone.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                            .foregroundStyle(milestone.isUnlocked ? Color.green : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(milestone.title).font(.subheadline.weight(.semibold))
                            Text(milestone.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(milestone.bonusPoints)").font(.caption.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(milestone.title). \(milestone.isUnlocked ? "Unlocked" : "Locked"). \(milestone.bonusPoints) points.")
                }
            }
        }
        .ownerScreen("Legacy")
        .messageAlert("Legacy", $message)
    }
}
