//
//  MailboxView.swift
//  Touchline
//
//  Inbox for club correspondence (news, transfer decisions, results) and a
//  browsable match history for the user's club.
//

import SwiftUI

// MARK: - Mailbox / Messages Hub

public struct MailboxView: View {
    @Environment(GameState.self) private var gameState
    @State private var filter: NewsCategory?
    @State private var unreadOnly = false
    @State private var confirmingDeleteAll = false

    private var inbox: [NewsItem] { gameState.news.filter { $0.isInboxMessage } }

    private var items: [NewsItem] {
        var result = inbox
        if unreadOnly { result = result.filter { !$0.isRead } }
        if let filter = filter { result = result.filter { $0.category == filter } }
        return result
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    Text(unreadCountLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Mark All Read") {
                        gameState.markAllMailRead()
                        try? SaveManager.shared.autoSave(gameState: gameState)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(gameState.unreadMailCount == 0)
                    .accessibilityLabel("Mark all messages as read")
                }
                Button("Delete All Messages", role: .destructive) {
                    confirmingDeleteAll = true
                }
                .disabled(inbox.isEmpty)
                // One dropdown for what to show, instead of a row of chips.
                Menu {
                    Picker("Show", selection: $filter) {
                        Text("All messages").tag(NewsCategory?.none)
                        ForEach(NewsCategory.allCases) { category in
                            Text(category.displayName).tag(NewsCategory?.some(category))
                        }
                    }
                    Toggle("Unread only", isOn: $unreadOnly)
                } label: {
                    HStack {
                        Text("Show: \(filter?.displayName ?? "All messages")\(unreadOnly ? ", unread only" : "")")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Filter messages")
                .accessibilityValue("\(filter?.displayName ?? "All messages")\(unreadOnly ? ", unread only" : "")")
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "Inbox Empty",
                    systemImage: "tray",
                    description: Text(unreadOnly ? "No unread messages." : "Club correspondence will appear here.")
                )
            } else {
                ForEach(dayGroups, id: \.date) { group in
                    Section(header: Text(Self.headerDate(group.date)).font(.gfLabel(14)).foregroundStyle(.white)) {
                        // Just the subject: tap it to open the message, with
                        // any actions it needs.
                        ForEach(group.items) { item in
                            NavigationLink {
                                MailDetailView(item: item)
                            } label: {
                                MailSubjectRow(item: item)
                            }
                            .accessibilityActions {
                                if !item.isRead {
                                    Button("Mark as Read") {
                                        gameState.markMailRead(id: item.id)
                                        try? SaveManager.shared.autoSave(gameState: gameState)
                                    }
                                }
                                Button("Delete", role: .destructive) {
                                    gameState.deleteMail(id: item.id)
                                    try? SaveManager.shared.autoSave(gameState: gameState)
                                }
                            }
                            .listRowBackground(item.isRead ? Color.gfSurface : Color(hex: "1E3E70"))
                        }
                    }
                }
            }
        }
        .listRowSpacing(8)
        .stadiumBackground()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all messages?", isPresented: $confirmingDeleteAll) {
            Button("Delete All", role: .destructive) {
                gameState.deleteAllMail()
                try? SaveManager.shared.autoSave(gameState: gameState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every inbox message, including messages hidden by your filters. Transfer offers remain available in Transfers.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    gameState.currentScreen = .dashboard
                }
                .accessibilityLabel("Close inbox")
            }
        }
    }

    /// Messages grouped by the day they arrived, newest day first.
    private var dayGroups: [(date: String, items: [NewsItem])] {
        var order: [String] = []
        var groups: [String: [NewsItem]] = [:]
        for item in items {
            if groups[item.date] == nil { order.append(item.date) }
            groups[item.date, default: []].append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "2026-08-11" → "TUESDAY 11 AUGUST 2026".
    static func headerDate(_ s: String) -> String {
        guard let d = parser.date(from: s) else { return s.uppercased() }
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: d).uppercased()
    }

    private var unreadCountLabel: String {
        let n = gameState.unreadMailCount
        return n == 0 ? "No unread messages" : "\(n) unread"
    }

    private var unreadChip: some View {
        Button {
            unreadOnly.toggle()
        } label: {
            Text("Unread")
                .font(.gfLabel(12))
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(unreadOnly ? Color.white : Color.gfNavy.opacity(0.85))
                .foregroundStyle(unreadOnly ? Color.gfNight : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(unreadOnly ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show unread messages only")
        .accessibilityAddTraits(unreadOnly ? .isSelected : [])
    }

    private func filterChip(_ category: NewsCategory?, label: String) -> some View {
        Button {
            filter = category
        } label: {
            Text(label)
                .font(.gfLabel(12))
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filter == category ? Color.white : Color.gfNavy.opacity(0.85))
                .foregroundStyle(filter == category ? Color.gfNight : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(filter == category ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(label)")
        .accessibilityAddTraits(filter == category ? .isSelected : [])
    }
}

/// An inbox line: who it's from and the subject.
struct MailSubjectRow: View {
    let item: NewsItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.headline)
                    .font(.subheadline.weight(item.isRead ? .regular : .bold))
                    .lineLimit(2)
                Text(item.sender)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !item.isRead {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.isRead ? "" : "Unread. ")\(item.headline). From \(item.sender)")
        .accessibilityHint("Opens the message")
    }
}

/// One message in full, with its actions; opening it marks it read.
struct MailDetailView: View {
    @Environment(GameState.self) private var gameState
    let item: NewsItem

    var body: some View {
        ScrollView {
            MailRow(item: item)
                .padding()
                .gfCard()
                .padding()
        }
        .stadiumBackground()
        .navigationTitle(item.sender)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { gameState.markMailRead(id: item.id) }
    }
}

struct MailRow: View {
    @Environment(GameState.self) private var gameState
    let item: NewsItem
    @State private var negotiatingOfferId: UUID?

    private var linkedOffer: TransferOffer? {
        guard let id = item.transferOfferId else { return nil }
        return gameState.pendingTransferOffers.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.sender)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !item.isRead {
                            Text("NEW")
                                .font(.gfLabel(11))
                                .foregroundStyle(Color.gfNight)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.white))
                                .accessibilityLabel("Unread")
                        }
                    }
                    Text(item.headline.uppercased())
                        .font(.gfLabel(15))
                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let offer = linkedOffer, offer.isLive {
                offerActions(offer)
                    .padding(.leading, 42)
            } else if let offer = linkedOffer {
                // Once settled, the message says how it ended instead of
                // silently losing its buttons.
                Label(settledText(offer), systemImage: offer.status == .completed ? "checkmark.seal.fill" : "xmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(offer.status == .completed ? Color.green : Color.secondary)
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.isRead ? "" : "Unread. ")From \(item.sender). \(item.category.displayName). \(item.headline). \(item.body)")
    }

    private func settledText(_ offer: TransferOffer) -> String {
        switch offer.status {
        case .completed: return offer.isLoan ? "Loan agreed" : "Deal completed"
        case .rejected: return offer.isIncoming ? "You rejected this offer" : "Deal off"
        case .withdrawn: return "Withdrawn"
        default: return offer.status.displayName
        }
    }

    @ViewBuilder
    private func offerActions(_ offer: TransferOffer) -> some View {
        let playerName = gameState.player(withId: offer.playerId)?.player.fullName ?? "the player"
        if offer.isIncoming {
            HStack(spacing: 10) {
                if !offer.isLoan {
                    Button {
                        negotiatingOfferId = offer.id
                    } label: {
                        Text("Negotiate").font(.gfLabel(13)).textCase(.uppercase)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .sheet(isPresented: Binding(get: { negotiatingOfferId == offer.id }, set: { if !$0 { negotiatingOfferId = nil } })) {
                        IncomingNegotiationView(offerId: offer.id)
                    }
                }
                Button {
                    gameState.acceptIncomingOffer(offerId: offer.id)
                } label: {
                    Label(offer.isLoan ? "Agree Loan" : "Accept \(Player.formatCurrency(offer.fee))", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    gameState.rejectIncomingOffer(offerId: offer.id)
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .accessibilityHint("Respond to the bid for \(playerName)")
        } else if offer.status == .counterOffer, let counter = offer.counterFee {
            HStack(spacing: 10) {
                Button {
                    gameState.acceptCounter(offerId: offer.id)
                } label: {
                    Label("Accept \(Player.formatCurrency(counter))", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    gameState.markMailRead(id: item.id)
                    gameState.negotiationTargetPlayerId = offer.playerId
                    gameState.currentScreen = .negotiation
                } label: {
                    Label("Counter", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    gameState.withdrawOffer(offerId: offer.id)
                } label: {
                    Label("Withdraw", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        } else if offer.status == .personalTerms, let demand = offer.demandedWage {
            HStack(spacing: 10) {
                Button {
                    gameState.bumpOffer(offerId: offer.id, newFee: offer.fee, newWage: demand)
                } label: {
                    Label("Pay \(Player.formatCurrency(demand))/w", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    gameState.withdrawOffer(offerId: offer.id)
                } label: {
                    Label("Withdraw", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Match History

public struct MatchHistoryView: View {
    @Environment(GameState.self) private var gameState
    @State private var showUpcoming = true

    private var played: [Fixture] {
        guard let id = gameState.userClubId else { return [] }
        return gameState.season.completedFixtures(forClub: id).reversed()
    }

    private var upcoming: [Fixture] {
        guard let id = gameState.userClubId else { return [] }
        return gameState.season.upcomingFixtures(forClub: id)
    }

    public var body: some View {
        List {
            Section {
                GFTabs(selection: $showUpcoming, options: [(true, "Upcoming (\(upcoming.count))"), (false, "Results (\(played.count))")])
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let userClub = gameState.userClub {
                let fixtures = showUpcoming ? upcoming : played
                if fixtures.isEmpty {
                    ContentUnavailableView(
                        showUpcoming ? "No Fixtures Left" : "No Matches Played",
                        systemImage: "sportscourt",
                        description: Text(showUpcoming ? "Your season's fixtures are complete." : "Your completed matches will be logged here.")
                    )
                } else {
                    let europe = gameState.userEuropeanFixtures.filter { showUpcoming ? !$0.fixture.isPlayed : $0.fixture.isPlayed }
                    if !europe.isEmpty {
                        Section("Europe") {
                            ForEach(europe.indices, id: \.self) { index in
                                europeanRow(europe[index].competition, europe[index].fixture, userClub: userClub)
                            }
                        }
                    }
                    Section(header: Text(showUpcoming ? "UPCOMING" : "RESULTS").font(.gfLabel(14)).foregroundStyle(.white)) {
                        ForEach(fixtures) { fixture in
                            FixtureCardRow(fixture: fixture, userClubId: userClub.id,
                                           derbyName: gameState.derbyName(for: fixture))
                                .listRowBackground(Color.gfSurface)
                        }
                    }
                }
            }
        }
        .listRowSpacing(6)
        .stadiumBackground()
        .navigationTitle("Team Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    gameState.currentScreen = .dashboard
                }
                .accessibilityLabel("Close fixtures and results")
            }
        }
    }

    private func europeanRow(_ competition: String, _ fixture: EuropeanFixture, userClub: Club) -> some View {
        let isHome = fixture.homeClubId == userClub.id
        let opponent = gameState.club(withId: isHome ? fixture.awayClubId : fixture.homeClubId)
        let goalsFor = isHome ? fixture.homeGoals : fixture.awayGoals
        let goalsAgainst = isHome ? fixture.awayGoals : fixture.homeGoals
        let stage = fixture.stage + (fixture.leg > 0 ? " (leg \(fixture.leg))" : "")
        return HStack(spacing: 12) {
            Image(systemName: "star.circle.fill").accessibilityHidden(true)
                .foregroundStyle(Color.goldAccent)
                .font(.title3)
            if let opponent { CrestView(club: opponent, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(isHome ? "vs" : "at") \(opponent?.name ?? "Opponent")")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(competition) • \(stage)")
                    .font(.caption)
                    .foregroundStyle(Color.goldAccent)
            }
            Spacer()
            if fixture.isPlayed {
                Text("\(goalsFor) - \(goalsAgainst)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fixture.isPlayed
            ? "\(competition), \(stage): \(goalsFor) \(goalsAgainst) \(isHome ? "at home to" : "away to") \(opponent?.name ?? "opponent")"
            : "\(competition), \(stage): \(isHome ? "home to" : "away to") \(opponent?.name ?? "opponent")")
    }
}

// MARK: - Shared Fixture / Result Row

public struct MatchResultRow: View {
    public let fixture: Fixture
    public let userClub: Club
    public let opponent: Club?
    public let derbyName: String?

    public init(fixture: Fixture, userClub: Club, opponent: Club?, derbyName: String? = nil) {
        self.fixture = fixture
        self.userClub = userClub
        self.opponent = opponent
        self.derbyName = derbyName
    }

    private var isHome: Bool { fixture.homeClubId == userClub.id }
    private var result: MatchResult? { fixture.isPlayed ? fixture.result : nil }
    private var goalsFor: Int { result.map { isHome ? $0.homeGoals : $0.awayGoals } ?? 0 }
    private var goalsAgainst: Int { result.map { isHome ? $0.awayGoals : $0.homeGoals } ?? 0 }
    private var outcome: String {
        guard result != nil else { return isHome ? "H" : "A" }
        if goalsFor > goalsAgainst { return "W" }
        if goalsFor < goalsAgainst { return "L" }
        return "D"
    }
    private var outcomeColor: Color {
        switch outcome {
        case "W": return .winGreen
        case "L": return .lossRed
        case "D": return .drawGray
        default: return .secondary
        }
    }
    private var competitionLabel: String {
        let base = fixture.cupRound.map { "\(fixture.competition) • \($0)" } ?? "\(fixture.competition) • MW \(fixture.matchWeek)"
        return derbyName.map { "\($0) • \(base)" } ?? base
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(outcome)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(outcomeColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let opponent {
                CrestView(club: opponent, size: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(isHome ? "vs" : "at") \(opponent?.name ?? "Opponent")")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(competitionLabel)
                    .font(.caption)
                    .foregroundStyle(derbyName != nil ? Color.lossRed : (fixture.isCupTie ? Color.goldAccent : .secondary))
                    .lineLimit(1)
                Text(fixture.date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if result != nil {
                Text("\(goalsFor) - \(goalsAgainst)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result != nil
            ? "\(outcome == "W" ? "Won" : outcome == "L" ? "Lost" : "Drew") \(goalsFor) \(goalsAgainst) \(isHome ? "at home to" : "away to") \(opponent?.name ?? "opponent"). \(competitionLabel). \(fixture.date)."
            : "\(isHome ? "Home to" : "Away to") \(opponent?.name ?? "opponent"), \(competitionLabel), \(fixture.date).")
    }
}


// MARK: - Selling: haggle over a bid

/// Two pages, like the buying screen: the player and the bid, then your
/// asking price with arrows. The buyer answers at once.
struct IncomingNegotiationView: View {
    @Environment(GameState.self) private var gameState
    @Environment(\.dismiss) private var dismiss
    let offerId: UUID
    @State private var page = 0
    @State private var request: Double = 0
    @State private var reply: String?
    @State private var finished = false

    private var offer: TransferOffer? { gameState.pendingTransferOffers.first { $0.id == offerId } }

    var body: some View {
        NavigationStack {
            Group {
                if let offer, let lookup = gameState.player(withId: offer.playerId) {
                    TabView(selection: $page) {
                        intro(offer: offer, player: lookup.player).tag(0)
                        haggle(offer: offer, player: lookup.player).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                } else {
                    ContentUnavailableView("Offer Closed", systemImage: "xmark.seal")
                }
            }
            .stadiumBackground()
            .navigationTitle("Negotiation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear {
                if request == 0, let offer {
                    request = Double(max(offer.fee, gameState.player(withId: offer.playerId)?.player.value ?? offer.fee))
                }
            }
        }
    }

    private func buyerName(_ offer: TransferOffer) -> String { gameState.club(withId: offer.toClubId)?.name ?? "The buyer" }

    private func chips(_ player: Player) -> some View {
        HStack(spacing: 18) {
            Text("\(player.overall)").font(.gfLabel(14)).foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 3).background(Capsule().fill(Color.white))
            Text("\(player.age) YEARS").font(.gfLabel(17))
            Text(player.primaryPosition.abbreviation).font(.gfLabel(14)).foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(player.primaryPosition.category.accentColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(player.overall), \(player.age) years old, \(player.primaryPosition.displayName)")
    }

    private func intro(offer: TransferOffer, player: Player) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(player.fullName.uppercased()).font(.gfDisplay(20)).multilineTextAlignment(.center)
                if let buyer = gameState.club(withId: offer.toClubId) {
                    HStack(spacing: 6) { CrestView(club: buyer, size: 18); Text(buyer.name).font(.headline) }
                }
                FaceView(player: player, size: 110, style: .full)
                    .frame(width: 170, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("TRANSFER OFFER").font(.gfDisplay(20))
                chips(player)
                HStack(spacing: 14) {
                    GFValuePill(title: "Market value", value: Player.formatCurrency(player.value))
                    GFValuePill(title: "Salary", value: "\(Player.formatCurrency(player.wage))/w")
                }
                .gfCard(padding: 14)
                Button("Start") { withAnimation { page = 1 } }
                    .buttonStyle(.gfOutline)
                    .padding(.horizontal, 70)
            }
            .padding()
            .padding(.bottom, 30)
        }
    }

    private func haggle(offer: TransferOffer, player: Player) -> some View {
        let step = max(10_000.0, (Double(player.value) / 20 / 10_000).rounded() * 10_000)
        return ScrollView {
            VStack(spacing: 14) {
                Text(player.fullName.uppercased())
                    .font(.gfDisplay(18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.gfNavy))
                    .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                Text(buyerName(offer)).font(.subheadline)
                chips(player)
                Text("TRANSFER OFFER").font(.gfLabel(15))
                Text(reply ?? "We are willing to offer \(Player.formatCurrency(offer.fee)) for your player. What do you think?")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.gfSurface))
                    .accessibilityAddTraits(.updatesFrequently)
                VStack(spacing: 10) {
                    Text("TRANSFER FEE").font(.gfDisplay(18))
                    HStack(spacing: 14) {
                        GFValuePill(title: "Market value", value: Player.formatCurrency(player.value))
                        GFValuePill(title: "Their offer", value: Player.formatCurrency(offer.fee), tone: .good)
                    }
                    Text("YOUR REQUEST").font(.gfLabel(14))
                    HStack {
                        Button { request = max(Double(offer.fee), request - step) } label: {
                            Image(systemName: "chevron.left").font(.headline.weight(.bold)).frame(width: 40, height: 36)
                        }
                        .accessibilityHidden(true)
                        Text(Player.formatCurrency(Int(request)))
                            .font(.gfDisplay(20).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.gfNavy))
                        Button { request += step } label: {
                            Image(systemName: "chevron.right").font(.headline.weight(.bold)).frame(width: 40, height: 36)
                        }
                        .accessibilityHidden(true)
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your asking price")
                    .accessibilityValue(Player.formatCurrency(Int(request)))
                    .accessibilityAdjustableAction { dir in
                        if dir == .increment { request += step } else { request = max(Double(offer.fee), request - step) }
                    }
                }
                .gfCard(padding: 14)
                if finished {
                    Button("Exit") { dismiss() }
                        .buttonStyle(.gfOutline)
                        .padding(.horizontal, 70)
                } else {
                    Button("Ask for \(Player.formatCurrency(Int(request)))") { ask(offer: offer, player: player) }
                        .buttonStyle(.gfPrimary)
                        .padding(.horizontal, 30)
                    HStack(spacing: 12) {
                        Button("Accept \(Player.formatCurrency(offer.fee))") {
                            gameState.acceptIncomingOffer(offerId: offer.id)
                            reply = "Deal done! \(player.lastName) joins \(buyerName(offer)) for \(Player.formatCurrency(offer.fee))."
                            finished = true
                        }
                        .buttonStyle(.gfSolid)
                        Button("Decline") {
                            gameState.rejectIncomingOffer(offerId: offer.id)
                            dismiss()
                        }
                        .buttonStyle(.gfDanger)
                    }
                }
            }
            .padding()
            .padding(.bottom, 30)
        }
    }

    private func ask(offer: TransferOffer, player: Player) {
        let buyer = buyerName(offer)
        switch gameState.counterIncomingOffer(offerId: offer.id, askingFee: Int(request)) {
        case .agreed(let fee):
            reply = "Deal done! We're happy to welcome \(player.lastName) for \(Player.formatCurrency(fee))."
            finished = true
        case .raised(let fee):
            reply = "That's too much. We can go to \(Player.formatCurrency(fee)), and that's close to our limit."
            request = max(request, Double(fee))
        case .walkedAway:
            reply = "\(buyer) have walked away. They felt your demands were unrealistic."
            finished = true
        case .unavailable:
            reply = "This offer is no longer available."
            finished = true
        }
        if let reply { AccessibilityNotification.Announcement(reply).post() }
        try? SaveManager.shared.autoSave(gameState: gameState)
    }
}


// MARK: - Calendar card

/// "LEEDS UNITED            WREXHAM": both names on top, crests below,
/// the date (or the score) in the middle.
struct FixtureCardRow: View {
    @Environment(GameState.self) private var gameState
    let fixture: Fixture
    let userClubId: UUID
    var derbyName: String? = nil

    var body: some View {
        let home = gameState.club(withId: fixture.homeClubId)
        let away = gameState.club(withId: fixture.awayClubId)
        let result = fixture.isPlayed ? fixture.result : nil
        let isHome = fixture.homeClubId == userClubId
        let outcome = result?.outcomeLetter(for: userClubId)
        VStack(spacing: 6) {
            HStack {
                Text((home?.name ?? "Home").uppercased())
                    .font(.gfLabel(14))
                    .fontWeight(isHome ? .black : .heavy)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text((away?.name ?? "Away").uppercased())
                    .font(.gfLabel(14))
                    .fontWeight(!isHome ? .black : .heavy)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                if let home { CrestView(club: home, size: 28) }
                Spacer()
                VStack(spacing: 2) {
                    if let result {
                        Text("\(result.homeGoals) - \(result.awayGoals)")
                            .font(.gfDisplay(22).monospacedDigit())
                            .foregroundStyle(outcome == "W" ? Color.gfMint : outcome == "L" ? Color.gfCoral : .white)
                    } else {
                        Image(systemName: fixture.isEuropean ? "star.circle.fill" : (fixture.cupRound != nil ? "trophy.fill" : "soccerball")).accessibilityHidden(true)
                            .font(.caption)
                            .foregroundStyle(fixture.isEuropean ? Color.goldAccent : .secondary)
                    }
                    Text(DashboardView.longDate(fixture.date).uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(fixture.cupRound.map { "\(fixture.competition) · \($0)" } ?? fixture.competition)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let derbyName {
                        Text(derbyName.uppercased()).font(.gfLabel(10)).foregroundStyle(Color.gfBanner)
                    }
                }
                Spacer()
                if let away { CrestView(club: away, size: 28) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(home: home, away: away, result: result, outcome: outcome))
    }

    private func spoken(home: Club?, away: Club?, result: MatchResult?, outcome: String?) -> String {
        let h = home?.name ?? "Home", a = away?.name ?? "Away"
        let when = DashboardView.longDate(fixture.date)
        if let result {
            let word = outcome == "W" ? "won" : outcome == "L" ? "lost" : "drew"
            return "\(fixture.competition), \(when): \(h) \(result.homeGoals), \(a) \(result.awayGoals). You \(word)."
        }
        return "\(fixture.competition), \(when): \(h) versus \(a)\(derbyName.map { ", \($0)" } ?? "")."
    }
}
