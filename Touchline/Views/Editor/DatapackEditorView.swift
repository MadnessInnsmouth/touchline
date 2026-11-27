//
//  DatapackEditorView.swift
//  Touchline
//
//  The editor: create datapacks from the game's data, change leagues,
//  clubs and players, choose which pack new careers use, and share packs
//  as files.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pack list

struct DatapackListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var active: String?
    @State private var newName = ""
    @State private var askingName = false
    @State private var importing = false
    @State private var message: String?
    @State private var deleting: String?
    @State private var busy = false

    private let store = DatapackStore.shared

    private func refresh() {
        names = store.list()
        active = store.activeName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GFScreenTitle(title: "Editor", subtitle: "Create and edit datapacks right inside the game")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("· Start from the game's own leagues, clubs and players")
                        Text("· Edit leagues, clubs, stadiums, managers and players")
                        Text("· Choose a pack and your next new career uses it")
                        Text("· Export a pack to a file, or import one")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gfCard()

                    Button(busy ? "Creating…" : "New Datapack") { newName = ""; askingName = true }
                        .buttonStyle(.gfSolid)
                        .disabled(busy)
                    Button("Import From File") { importing = true }
                        .buttonStyle(.gfOutline)

                    activeCard(name: nil)
                    ForEach(names, id: \.self) { name in
                        activeCard(name: name)
                    }
                }
                .padding()
            }
            .stadiumBackground()
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: refresh)
            .alert("Name your datapack", isPresented: $askingName) {
                TextField("My Datapack", text: $newName)
                Button("Create") { create() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It starts as a copy of the game's current data.")
            }
            .alert("Editor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
            .confirmationDialog("Delete \(deleting ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let name = deleting { store.delete(name) }
                    deleting = nil
                    refresh()
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result, let pack = store.importPack(from: url) {
                    message = "Imported \(pack.name): \(pack.clubCount) clubs and \(pack.playerCount) players."
                } else {
                    message = "Could not import this file. Choose a valid Touchline datapack and check that your device has free storage."
                }
                refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func create() {
        busy = true
        let name = newName
        DispatchQueue.global(qos: .userInitiated).async {
            let pack = store.createFromBundled(named: name)
            DispatchQueue.main.async {
                busy = false
                if let pack {
                    message = "Created \(pack.name) with \(pack.leagues.count) leagues, \(pack.clubCount) clubs and \(pack.playerCount) players."
                } else {
                    message = "Could not create the datapack."
                }
                refresh()
            }
        }
    }

    /// One pack (or the game's own data when `name` is nil) as a card.
    private func activeCard(name: String?) -> some View {
        let isActive = active == name
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((name ?? "Touchline 2026/27 data").uppercased()).font(.gfDisplay(19)).lineLimit(2)
                Spacer()
                if isActive {
                    Text("IN USE").font(.gfLabel(12)).foregroundStyle(Color.gfNight)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Color.gfMint))
                }
            }
            Text(name == nil ? "The leagues, clubs and players that come with the game." : "Your datapack. New careers can be built from it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if !isActive {
                    Button("Use") {
                        store.activeName = name
                        refresh()
                        message = "New careers will now use \(name ?? "the game's own data"). Careers already in progress are not changed."
                    }
                    .buttonStyle(.gfSolid)
                }
                if let name {
                    NavigationLink("Edit") { DatapackEditView(name: name) }
                        .buttonStyle(.gfOutline)
                }
            }
            if let name {
                HStack(spacing: 18) {
                    ShareLink(item: store.fileURL(for: name)) { Label("Export", systemImage: "square.and.arrow.up") }
                    Button {
                        if let copy = store.duplicate(name) {
                            message = "Copied as \(copy.name)."
                        } else {
                            message = "Could not duplicate \(name)."
                        }
                        refresh()
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Spacer()
                    Button(role: .destructive) { deleting = name } label: { Label("Delete", systemImage: "trash") }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .gfCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - One pack

struct DatapackEditView: View {
    let name: String
    @State private var pack: Datapack?
    @State private var search = ""
    @State private var dirty = false
    @State private var loadFailed = false
    @State private var saveFailed = false

    var body: some View {
        Group {
            if pack != nil {
                List {
                    Section(footer: Text("\(pack?.leagues.count ?? 0) leagues · \(pack?.clubCount ?? 0) clubs · \(pack?.playerCount ?? 0) players. Changes are saved when you leave this screen.")) {
                        let visibleIndices = visibleLeagueIndices
                        ForEach(visibleIndices, id: \.self) { index in
                            if let league = pack?.leagues[index] {
                                NavigationLink {
                                    LeagueEditView(pack: Binding(get: { pack! }, set: { pack = $0; dirty = true }), leagueIndex: index, search: search)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(league.name).font(.headline)
                                        Text("\(LeagueTier(rawValue: league.tier).map { "\($0.country.displayName), division \($0.level) · " } ?? "")\(league.clubs.count) clubs")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let leagueOffsets = IndexSet(offsets.map { visibleIndices[$0] })
                            pack?.leagues.remove(atOffsets: leagueOffsets)
                            dirty = true
                        }
                    }
                    Section(footer: Text("A new league starts with four placeholder clubs; edit them, or move clubs in from other leagues.")) {
                        Menu {
                            ForEach(availableTiers, id: \.rawValue) { tier in
                                Button("\(tier.country.displayName): \(tier.displayName)") { addLeague(tier) }
                            }
                        } label: {
                            Label("Add a League", systemImage: "plus.circle.fill")
                        }
                        .disabled(availableTiers.isEmpty)
                    }
                }
                .searchable(text: $search, prompt: "League or club")
            } else if loadFailed {
                ContentUnavailableView("Could not open datapack", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Loading…")
            }
        }
        .stadiumBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if pack == nil {
                pack = DatapackStore.shared.load(name)
                loadFailed = pack == nil
            }
        }
        .onDisappear(perform: save)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save).disabled(!dirty)
            }
        }
        .alert("Could not save datapack", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that your device has free storage, then try saving again.")
        }
    }

    private var visibleLeagueIndices: [Int] {
        guard let leagues = pack?.leagues else { return [] }
        return leagues.indices.filter { index in
            let league = leagues[index]
            return search.isEmpty || league.name.localizedCaseInsensitiveContains(search)
                || league.clubs.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    /// Divisions not yet in the pack (in countries whose leagues are in the game).
    private var availableTiers: [LeagueTier] {
        let used = Set((pack?.leagues ?? []).map(\.tier))
        return LeagueTier.allCases.filter { $0.country.hasClubLeagues && !used.contains($0.rawValue) }
    }

    private func addLeague(_ tier: LeagueTier) {
        let clubs = (1...4).map { n in
            RawClubData(name: "New Club \(n)", shortName: "NC\(n)", stadium: "New Stadium", stadiumCapacity: 10_000,
                        primaryColor: "#1565C0", secondaryColor: "#FFFFFF", city: "City", manager: "Head Coach",
                        reputation: 50, budget: 0, wageBudget: 0, players: [])
        }
        pack?.leagues.append(RawLeagueData(name: tier.displayName, tier: tier.rawValue, clubs: clubs))
        dirty = true
    }

    private func save() {
        guard dirty, let pack else { return }
        guard DatapackStore.shared.save(pack) else {
            saveFailed = true
            return
        }
        dirty = false
    }
}

// MARK: - League

struct LeagueEditView: View {
    @Binding var pack: Datapack
    let leagueIndex: Int
    var search: String = ""
    @State private var moving = false

    private var valid: Bool { pack.leagues.indices.contains(leagueIndex) }

    var body: some View {
        List {
            if valid {
                Section("League") {
                    TextField("League name", text: $pack.leagues[leagueIndex].name)
                        .accessibilityLabel("League name")
                }
                Section(header: Text("Clubs"), footer: Text("Swipe a club to delete it. A league needs at least two clubs to produce fixtures. With an odd number, one club sits out each round.")) {
                    ForEach(Array(pack.leagues[leagueIndex].clubs.enumerated()), id: \.offset) { index, club in
                        NavigationLink {
                            ClubEditView(pack: $pack, leagueIndex: leagueIndex, clubIndex: index)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: club.primaryColor)).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white.opacity(0.4)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(club.name).font(.subheadline.weight(.semibold))
                                    Text("Reputation \(club.reputation) · \(club.players.count) players").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        pack.leagues[leagueIndex].clubs.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        pack.leagues[leagueIndex].clubs.move(fromOffsets: from, toOffset: to)
                    }
                    Button {
                        let n = pack.leagues[leagueIndex].clubs.count + 1
                        pack.leagues[leagueIndex].clubs.append(RawClubData(
                            name: "New Club \(n)", shortName: "NEW", stadium: "New Stadium", stadiumCapacity: 10_000,
                            primaryColor: "#1565C0", secondaryColor: "#FFFFFF", city: "City", manager: "Head Coach",
                            reputation: 50, budget: 0, wageBudget: 0, players: []))
                    } label: { Label("Add Club", systemImage: "plus.circle.fill") }
                }
            }
        }
        .stadiumBackground()
        .navigationTitle(valid ? pack.leagues[leagueIndex].name : "League")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }
}

// MARK: - Sliders

/// A labelled slider for a whole number, with its value shown and spoken.
/// VoiceOver swipes up or down to change it a step at a time.
struct EditorSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                    set: { value = Int(($0 / Double(step)).rounded()) * step }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// Amounts in the editor are kept in pounds.
private func editorMoney(_ amount: Int) -> String {
    if amount >= 1_000_000 { return String(format: "£%.1fM", Double(amount) / 1_000_000) }
    if amount >= 1_000 { return "£\(amount / 1_000)K" }
    return "£\(amount)"
}

// MARK: - Club

struct ClubEditView: View {
    @Binding var pack: Datapack
    let leagueIndex: Int
    let clubIndex: Int
    @State private var movingLeague = false
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool {
        pack.leagues.indices.contains(leagueIndex) && pack.leagues[leagueIndex].clubs.indices.contains(clubIndex)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<RawClubData, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: pack.leagues[leagueIndex].clubs[clubIndex][keyPath: keyPath]) },
            set: { pack.leagues[leagueIndex].clubs[clubIndex][keyPath: keyPath] = $0.hexString }
        )
    }

    /// An optional whole number shown with a default until it is set.
    private func optional(_ keyPath: WritableKeyPath<RawClubData, Int?>, default value: Int) -> Binding<Int> {
        Binding(
            get: { pack.leagues[leagueIndex].clubs[clubIndex][keyPath: keyPath] ?? value },
            set: { pack.leagues[leagueIndex].clubs[clubIndex][keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        List {
            if valid {
                let club = $pack.leagues[leagueIndex].clubs[clubIndex]
                Section("Club") {
                    LabeledContent("Name") { TextField("Name", text: club.name).multilineTextAlignment(.trailing) }
                    LabeledContent("Short name") {
                        TextField("ABC", text: club.shortName).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                    }
                    LabeledContent("City") { TextField("City", text: club.city).multilineTextAlignment(.trailing) }
                    LabeledContent("Manager") { TextField("Manager", text: club.manager).multilineTextAlignment(.trailing) }
                    EditorSlider(title: "Reputation", value: club.reputation, range: 1...99,
                                 note: "How big the club is: crowds, money, which players will join.")
                }
                Section("Stadium") {
                    LabeledContent("Name") { TextField("Stadium", text: club.stadium).multilineTextAlignment(.trailing) }
                    EditorSlider(title: "Capacity", value: club.stadiumCapacity, range: 500...120_000, step: 500,
                                 format: { $0.formatted() })
                }
                Section(header: Text("Money"), footer: Text("Left at zero, the game sets them from the club's size.")) {
                    EditorSlider(title: "Transfer budget", value: optional(\.budget, default: 0),
                                 range: 0...400_000_000, step: 250_000,
                                 format: { $0 == 0 ? "Automatic" : editorMoney($0) })
                    EditorSlider(title: "Weekly wage budget", value: optional(\.wageBudget, default: 0),
                                 range: 0...6_000_000, step: 5_000,
                                 format: { $0 == 0 ? "Automatic" : editorMoney($0) + "/w" })
                    EditorSlider(title: "Bank balance", value: optional(\.balance, default: 0),
                                 range: 0...1_000_000_000, step: 1_000_000,
                                 format: { $0 == 0 ? "Automatic" : editorMoney($0) })
                }
                Section(header: Text("Facilities"), footer: Text("1 is basic, 5 is the best in the world.")) {
                    EditorSlider(title: "Training ground", value: optional(\.trainingLevel, default: 2), range: 1...5)
                    EditorSlider(title: "Youth academy", value: optional(\.academyLevel, default: 2), range: 1...5)
                    EditorSlider(title: "Medical department", value: optional(\.medicalLevel, default: 2), range: 1...5)
                }
                Section("Colours") {
                    ColorPicker("Primary", selection: colorBinding(\.primaryColor), supportsOpacity: false)
                    ColorPicker("Secondary", selection: colorBinding(\.secondaryColor), supportsOpacity: false)
                }
                Section(header: Text("Players (\(club.wrappedValue.players.count))"),
                        footer: Text("Swipe to delete. A club with fewer than 18 players is topped up with generated ones.")) {
                    ForEach(Array(club.wrappedValue.players.enumerated()), id: \.offset) { index, player in
                        NavigationLink {
                            PlayerEditView(pack: $pack, leagueIndex: leagueIndex, clubIndex: clubIndex, playerIndex: index)
                        } label: {
                            HStack {
                                Text(player.positions.first ?? "CM")
                                    .font(.gfLabel(12)).foregroundStyle(.black)
                                    .frame(width: 40).padding(.vertical, 3)
                                    .background(Capsule().fill((Position(rawValue: player.positions.first ?? "CM") ?? .CM).category.accentColor))
                                Text("\(player.firstName) \(player.lastName)".trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline)
                                Spacer()
                                Text("\(player.age)").font(.caption).foregroundStyle(.secondary)
                                Text("\(player.overall)").font(.gfLabel(14).monospacedDigit())
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(player.firstName) \(player.lastName), \(player.positions.first ?? ""), age \(player.age), rated \(player.overall)")
                        }
                    }
                    .onDelete { offsets in
                        pack.leagues[leagueIndex].clubs[clubIndex].players.remove(atOffsets: offsets)
                    }
                    Button {
                        pack.leagues[leagueIndex].clubs[clubIndex].players.append(RawPlayerData(
                            firstName: "New", lastName: "Player", nationality: "England", age: 21, positions: ["CM"],
                            overall: 60, potential: 70, preferredFoot: "right", height: nil, weight: nil, value: nil,
                            wage: nil, contractYears: nil, specialties: nil))
                    } label: { Label("Add Player", systemImage: "plus.circle.fill") }
                }
                Section(footer: Text("Moving a club takes its whole squad with it.")) {
                    Button { movingLeague = true } label: {
                        Label("Move to Another League", systemImage: "arrow.up.arrow.down")
                    }
                    Button {
                        var copy = pack.leagues[leagueIndex].clubs[clubIndex]
                        copy.name += " (copy)"
                        pack.leagues[leagueIndex].clubs.append(copy)
                    } label: {
                        Label("Duplicate Club", systemImage: "plus.square.on.square")
                    }
                }
            }
        }
        .stadiumBackground()
        .navigationTitle(valid ? pack.leagues[leagueIndex].clubs[clubIndex].name : "Club")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $movingLeague) {
            NavigationStack {
                List {
                    ForEach(Array(pack.leagues.enumerated()), id: \.offset) { li, league in
                        if li != leagueIndex {
                            Button("\(league.name) (\(league.clubs.count) clubs)") {
                                guard valid else { return }
                                let club = pack.leagues[leagueIndex].clubs.remove(at: clubIndex)
                                pack.leagues[li].clubs.append(club)
                                movingLeague = false
                                dismiss()
                            }
                        }
                    }
                }
                .navigationTitle("Move To")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { movingLeague = false } } }
            }
        }
    }
}

// MARK: - Player

struct PlayerEditView: View {
    @Binding var pack: Datapack
    let leagueIndex: Int
    let clubIndex: Int
    let playerIndex: Int
    @State private var choosingClub = false
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool {
        pack.leagues.indices.contains(leagueIndex)
            && pack.leagues[leagueIndex].clubs.indices.contains(clubIndex)
            && pack.leagues[leagueIndex].clubs[clubIndex].players.indices.contains(playerIndex)
    }

    /// Every attribute, grouped as on the player screen. The key is how
    /// the datapack stores it (see DataLoader's specialties).
    private static let attributeGroups: [(String, [(String, String)])] = [
        ("Technical", [("Passing", "passing"), ("Shooting", "shooting"), ("Dribbling", "dribbling"),
                       ("First touch", "firsttouch"), ("Crossing", "crossing"), ("Free kicks", "freekicks"),
                       ("Penalties", "penalties"), ("Heading", "heading"), ("Long shots", "longshots"),
                       ("Tackling", "tackling"), ("Marking", "marking")]),
        ("Physical", [("Pace", "pace"), ("Stamina", "stamina"), ("Strength", "strength"), ("Agility", "agility"),
                      ("Jumping", "jumping"), ("Balance", "balance")]),
        ("Mental", [("Vision", "vision"), ("Composure", "composure"), ("Decisions", "decisions"),
                    ("Work rate", "workrate"), ("Aggression", "aggression"), ("Leadership", "leadership"),
                    ("Teamwork", "teamwork"), ("Positioning", "positioning"), ("Off the ball", "offtheball"),
                    ("Concentration", "concentration")]),
        ("Goalkeeping", [("Reflexes", "reflexes"), ("Handling", "handling"), ("Positioning (GK)", "gkpositioning"),
                         ("One on ones", "oneonones"), ("Kicking", "kicking"), ("Command of area", "commandofarea")])
    ]

    var body: some View {
        List {
            if valid {
                let player = $pack.leagues[leagueIndex].clubs[clubIndex].players[playerIndex]
                Section("Player") {
                    LabeledContent("First name") { TextField("First name", text: player.firstName).multilineTextAlignment(.trailing) }
                    LabeledContent("Last name") { TextField("Last name", text: player.lastName).multilineTextAlignment(.trailing) }
                    LabeledContent("Nationality") { TextField("Nationality", text: player.nationality).multilineTextAlignment(.trailing) }
                    EditorSlider(title: "Age", value: player.age, range: 15...45)
                    Picker("Preferred foot", selection: Binding(
                        get: { player.wrappedValue.preferredFoot ?? "right" },
                        set: { player.wrappedValue.preferredFoot = $0 })) {
                        Text("Right").tag("right")
                        Text("Left").tag("left")
                        Text("Both").tag("both")
                    }
                    EditorSlider(title: "Height", value: Binding(
                        get: { player.wrappedValue.height ?? 181 },
                        set: { player.wrappedValue.height = $0 }), range: 155...210, format: { "\($0) cm" })
                    EditorSlider(title: "Weight", value: Binding(
                        get: { player.wrappedValue.weight ?? 76 },
                        set: { player.wrappedValue.weight = $0 }), range: 50...110, format: { "\($0) kg" })
                }
                Section("Position") {
                    Picker("Main position", selection: Binding(
                        get: { player.wrappedValue.positions.first ?? "CM" },
                        set: { new in
                            var others = player.wrappedValue.positions.dropFirst().filter { $0 != new }
                            others.insert(new, at: others.startIndex)
                            player.wrappedValue.positions = Array(others)
                        })) {
                        ForEach(Position.allCases) { pos in Text("\(pos.rawValue) · \(pos.displayName)").tag(pos.rawValue) }
                    }
                    Picker("Second position", selection: Binding(
                        get: { player.wrappedValue.positions.count > 1 ? player.wrappedValue.positions[1] : "" },
                        set: { new in
                            let main = player.wrappedValue.positions.first ?? "CM"
                            player.wrappedValue.positions = new.isEmpty || new == main ? [main] : [main, new]
                        })) {
                        Text("None").tag("")
                        ForEach(Position.allCases) { pos in Text(pos.rawValue).tag(pos.rawValue) }
                    }
                }
                Section(header: Text("Ability"), footer: Text("Rating is how good he is now; potential is how good he can become.")) {
                    EditorSlider(title: "Rating", value: Binding(
                        get: { player.wrappedValue.overall },
                        set: { player.wrappedValue.overall = $0; if player.wrappedValue.potential < $0 { player.wrappedValue.potential = $0 } }),
                                 range: 30...99)
                    EditorSlider(title: "Potential", value: Binding(
                        get: { player.wrappedValue.potential },
                        set: { player.wrappedValue.potential = max($0, player.wrappedValue.overall) }), range: 30...99)
                }
                Section(header: Text("Contract"), footer: Text("Left at zero, wage and value are worked out from his rating and age.")) {
                    EditorSlider(title: "Weekly wage", value: Binding(
                        get: { player.wrappedValue.wage ?? 0 },
                        set: { player.wrappedValue.wage = $0 == 0 ? nil : $0 }),
                                 range: 0...600_000, step: 500,
                                 format: { $0 == 0 ? "Automatic" : editorMoney($0) + "/w" })
                    EditorSlider(title: "Years left", value: Binding(
                        get: { player.wrappedValue.contractYears ?? 3 },
                        set: { player.wrappedValue.contractYears = $0 }), range: 1...6)
                    EditorSlider(title: "Market value", value: Binding(
                        get: { player.wrappedValue.value ?? 0 },
                        set: { player.wrappedValue.value = $0 == 0 ? nil : $0 }),
                                 range: 0...250_000_000, step: 250_000,
                                 format: { $0 == 0 ? "Automatic" : editorMoney($0) })
                }
                ForEach(Self.attributeGroups, id: \.0) { group in
                    Section(header: Text(group.0),
                            footer: group.0 == "Technical"
                                ? Text("Attributes left on Automatic are generated from his rating and position. Move a slider to set one exactly.")
                                : nil) {
                        ForEach(group.1, id: \.1) { attribute in
                            let key = attribute.1
                            EditorSlider(title: attribute.0, value: Binding(
                                get: { player.wrappedValue.specialties?[key] ?? 0 },
                                set: { new in
                                    var specs = player.wrappedValue.specialties ?? [:]
                                    specs[key] = new == 0 ? nil : new
                                    player.wrappedValue.specialties = specs.isEmpty ? nil : specs
                                }), range: 0...99, format: { $0 == 0 ? "Automatic" : "\($0)" })
                        }
                    }
                }
                Section {
                    Button("Reset All Attributes to Automatic") { player.wrappedValue.specialties = nil }
                    Button {
                        var copy = player.wrappedValue
                        copy.lastName += " II"
                        pack.leagues[leagueIndex].clubs[clubIndex].players.append(copy)
                    } label: { Label("Duplicate Player", systemImage: "plus.square.on.square") }
                    Button { choosingClub = true } label: { Label("Move to Another Club", systemImage: "arrow.left.arrow.right") }
                }
            }
        }
        .stadiumBackground()
        .navigationTitle(valid ? pack.leagues[leagueIndex].clubs[clubIndex].players[playerIndex].lastName : "Player")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosingClub) {
            ClubChooser(pack: pack) { li, ci in
                guard valid, !(li == leagueIndex && ci == clubIndex) else { return }
                let player = pack.leagues[leagueIndex].clubs[clubIndex].players.remove(at: playerIndex)
                pack.leagues[li].clubs[ci].players.append(player)
                dismiss()
            }
        }
    }
}

/// A searchable list of every club in the pack.
private struct ClubChooser: View {
    let pack: Datapack
    let onChoose: (Int, Int) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pack.leagues.enumerated()), id: \.offset) { li, league in
                    let clubs = Array(league.clubs.enumerated()).filter { search.isEmpty || $0.element.name.localizedCaseInsensitiveContains(search) }
                    if !clubs.isEmpty {
                        Section(league.name) {
                            ForEach(clubs, id: \.offset) { ci, club in
                                Button(club.name) {
                                    dismiss()
                                    onChoose(li, ci)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Club")
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

extension Color {
    /// "#RRGGBB" for storing a picked colour.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
