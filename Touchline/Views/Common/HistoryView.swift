//
//  HistoryView.swift
//  Touchline
//
//  The record books: the club's trophy cabinet, its Hall of Fame, the roll
//  of honour for every competition, and the world's individual awards.
//

import SwiftUI

struct HistoryView: View {
    @Environment(GameState.self) private var gameState
    @State private var section: Section = .trophies
    @State private var competition: String = ""

    enum Section: String, CaseIterable, Identifiable {
        case trophies = "Trophies"
        case records = "Records"
        case legends = "Hall of Fame"
        case champions = "Champions"
        case awards = "Awards"
        case achievements = "Goals"
        var id: String { rawValue }
    }

    private var history: WorldHistory { gameState.history }

    var body: some View {
        List {
            GFTabs(selection: $section, compact: true)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            switch section {
            case .trophies: trophies
            case .records: records
            case .legends: legends
            case .champions: champions
            case .awards: awards
            case .achievements: achievementsSection
            }
        }
        .stadiumBackground()
        .navigationTitle("Club History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
            }
        }
        .onAppear {
            if competition.isEmpty { competition = competitions.first ?? "" }
        }
    }

    // MARK: Trophy cabinet

    @ViewBuilder
    private var trophies: some View {
        if let club = gameState.userClub {
            let won = gameState.trophyCabinet(for: club)
            if won.isEmpty {
                SwiftUI.Section {
                    ContentUnavailableView("The Cabinet Is Empty",
                                           systemImage: "trophy",
                                           description: Text("\(club.name) has won 0 trophies in this career."))
                }
            } else {
                let grouped = Dictionary(grouping: won, by: { $0.competition })
                let competitions = grouped.keys.sorted { lhs, rhs in
                    let left = grouped[lhs]?.count ?? 0
                    let right = grouped[rhs]?.count ?? 0
                    return left == right ? lhs < rhs : left > right
                }
                SwiftUI.Section(header: Text("\(club.name), \(won.count) \(won.count == 1 ? "trophy" : "trophies")")) {
                    ForEach(competitions, id: \.self) { name in
                        let wins = grouped[name] ?? []
                        HStack(spacing: 14) {
                            Image(systemName: icon(for: wins.first?.kind ?? .cup)).accessibilityHidden(true)
                                .font(.title2)
                                .foregroundStyle(Color(hex: "D4AF37"))
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.headline)
                                Text(wins.map { $0.season }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("×\(wins.count)")
                                .font(.title3.weight(.bold).monospacedDigit())
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(name), \(wins.count) \(wins.count == 1 ? "trophy" : "trophies"). \(wins.map { $0.season }.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var records: some View {
        let book = gameState.clubRecords
        if let club = gameState.userClub, book.clubId == club.id, book.matchesTracked > 0 {
            SwiftUI.Section(header: Text("Since you took charge")) {
                LabeledContent("Matches tracked", value: book.matchesTracked.formatted())
                LabeledContent("Biggest win", value: book.biggestWin > 0 ? book.biggestWinText : "None yet")
                LabeledContent("Heaviest defeat", value: book.heaviestDefeat > 0 ? book.heaviestDefeatText : "None yet")
                LabeledContent("Highest home attendance", value: book.recordCrowd > 0 ? book.recordCrowd.formatted() : "None yet")
            }
        } else {
            ContentUnavailableView("No Club Records Yet", systemImage: "book.closed",
                                   description: Text("Records appear after you play a match with your club."))
        }
    }

    // MARK: Hall of Fame

    @ViewBuilder
    private var legends: some View {
        if let club = gameState.userClub {
            let book = history.legends(for: club.id)
            if book.isEmpty {
                SwiftUI.Section {
                    ContentUnavailableView("No Legends Yet",
                                           systemImage: "star",
                                           description: Text("At the end of each season, everyone who played for \(club.name) is added here."))
                }
            } else {
                SwiftUI.Section(header: Text("Most appearances")) {
                    ForEach(Array(book.prefix(15).enumerated()), id: \.element.id) { index, legend in
                        legendRow(rank: index + 1, legend: legend, highlight: "\(legend.appearances) apps")
                    }
                }
                let scorers = book.filter { $0.goals > 0 }.sorted { $0.goals > $1.goals }.prefix(10)
                if !scorers.isEmpty {
                    SwiftUI.Section(header: Text("Top scorers")) {
                        ForEach(Array(scorers.enumerated()), id: \.element.id) { index, legend in
                            legendRow(rank: index + 1, legend: legend, highlight: "\(legend.goals) goals")
                        }
                    }
                }
            }
        }
    }

    private func legendRow(rank: Int, legend: LegendRecord, highlight: String) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color(hex: "D4AF37") : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(legend.name).font(.subheadline.weight(.semibold))
                Text("\(legend.position) • \(legend.firstSeason == legend.lastSeason ? legend.firstSeason : "\(legend.firstSeason)–\(legend.lastSeason)") • best \(legend.bestRating)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(highlight).font(.subheadline.weight(.bold).monospacedDigit())
                Text(legend.position == "GK" ? "\(legend.appearances) apps" : "\(legend.appearances) apps • \(legend.goals) g • \(legend.assists) a")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Roll of honour

    /// The user's leagues and cups first, then Europe, then everything else.
    private var competitions: [String] {
        var names: [String] = []
        if let club = gameState.userClub {
            let country = club.leagueTier.country
            names += gameState.leagues.filter { $0.tier.country == country }
                .sorted { $0.tier.level < $1.tier.level }.map { $0.name }
            names += gameState.domesticCups.filter { $0.country == country }.map { $0.name }
        }
        names += EuropeanCompetition.allCases.map { $0.displayName }
        let recorded = Set(history.honours.map { $0.competition })
        names += recorded.subtracting(names).sorted()
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private var champions: some View {
        SwiftUI.Section {
            Picker("Competition", selection: $competition) {
                ForEach(competitions, id: \.self) { Text($0).tag($0) }
            }
        }
        let winners = history.champions(of: competition)
        if winners.isEmpty {
            SwiftUI.Section {
                Text("No champions recorded yet. The roll of honour fills in at the end of each season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            let titles = Dictionary(grouping: winners, by: { $0.clubName }).mapValues { $0.count }
            SwiftUI.Section(header: Text("Roll of honour")) {
                ForEach(winners) { record in
                    HStack {
                        Text(record.season)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.clubName)
                                .font(.subheadline.weight(record.clubId == gameState.userClubId ? .bold : .semibold))
                                .foregroundStyle(record.clubId == gameState.userClubId ? Color.accentColor : .primary)
                            if let runnerUp = record.runnerUpName {
                                Text("Runners-up: \(runnerUp)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: icon(for: record.kind)).accessibilityHidden(true)
                            .foregroundStyle(Color(hex: "D4AF37"))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            SwiftUI.Section(header: Text("Most titles")) {
                ForEach(titles.sorted { $0.value > $1.value }.prefix(5), id: \.key) { name, count in
                    LabeledContent(name, value: "\(count)")
                }
            }
        }
    }

    // MARK: Awards

    @ViewBuilder
    private var awards: some View {
        if history.awards.isEmpty {
            SwiftUI.Section {
                ContentUnavailableView("No Awards Yet",
                                       systemImage: "medal",
                                       description: Text("The world's best player, young player, goalkeeper and top scorer are crowned at the end of every season."))
            }
        } else {
            let seasons = Array(Set(history.awards.map { $0.season })).sorted(by: >)
            ForEach(seasons, id: \.self) { year in
                SwiftUI.Section(header: Text(year)) {
                    ForEach(history.awards.filter { $0.season == year }) { award in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(award.award).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("\(award.playerName) • \(award.clubName)").font(.subheadline.weight(.semibold))
                            Text(award.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Achievements

    @ViewBuilder
    private var achievementsSection: some View {
        let list = gameState.achievementList
        let unlocked = list.filter { $0.unlockedOn != nil }.count
        SwiftUI.Section(header: Text("\(unlocked) of \(list.count) unlocked")) {
            ProgressView(value: Double(unlocked), total: Double(max(1, list.count)))
            ForEach(list, id: \.achievement.id) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.achievement.icon).accessibilityHidden(true)
                        .font(.title3)
                        .foregroundStyle(entry.unlockedOn != nil ? Color(hex: "D4AF37") : Color.secondary.opacity(0.4))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.achievement.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(entry.unlockedOn != nil ? .primary : .secondary)
                        Text(entry.achievement.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let date = entry.unlockedOn {
                        Text(date).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "lock.fill").accessibilityHidden(true).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.achievement.title), \(entry.unlockedOn != nil ? "unlocked" : "locked"). \(entry.achievement.detail)")
            }
        }
    }

    private func icon(for kind: HonourRecord.Kind) -> String {
        switch kind {
        case .league: return "trophy.fill"
        case .cup: return "trophy"
        case .europe: return "star.circle.fill"
        }
    }
}
